defmodule Queuetopia.Queue do
  @moduledoc false

  import Ecto.Query

  alias Queuetopia.Queue.{Job, Lock, PendingQueue}
  alias Queuetopia.Queue.JobQueryable
  alias Queuetopia.Queue.PendingQueueQueryable

  @lock_security_retention 1_000

  @type list_options :: [option] | []

  @type option :: {:filters, keyword} | {:search_query, binary}

  @doc """
  List jobs by options.
  """
  @spec list_jobs(module, list_options) :: [Job.t()]
  def list_jobs(repo, opts \\ []) do
    job_queryable(opts) |> repo.all()
  end

  @doc """
  Paginate jobs
  """
  @spec paginate_jobs(module, pos_integer, pos_integer, list_options) :: %{
          data: [Job.t()],
          total: any,
          page_size: pos_integer,
          page_number: pos_integer
        }
  def paginate_jobs(repo, page_size, page_number, opts \\ [])
      when is_integer(page_number) and is_integer(page_size) do
    query = job_queryable(opts)

    %{
      data: query |> JobQueryable.paginate(page_size, page_number) |> repo.all(),
      total: query |> repo.aggregate(:count, :id),
      page_number: page_number,
      page_size: page_size
    }
  end

  defp job_queryable(opts) do
    filters = Keyword.get(opts, :filters, [])
    search_query = Keyword.get(opts, :search_query)
    order_bys = Keyword.get(opts, :order_by_fields, desc: :sequence)

    JobQueryable.queryable()
    |> JobQueryable.filter(filters)
    |> JobQueryable.search(search_query)
    |> JobQueryable.order_by(order_bys)
  end

  @doc """
  Creates a job, specifying the Queuetopia (scope), and the user params,
  including options.
  """

  @spec create_job(map, module) :: {:error, Ecto.Changeset.t()} | {:ok, Job.t()}
  def create_job(attrs, repo) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:job, Job.create_changeset(attrs))
    |> Ecto.Multi.run(:pending_queue, fn repo, %{job: job} ->
      {:ok, upsert_pending_queue(repo, job)}
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{job: job}} -> {:ok, job}
      {:error, :job, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
    end
  end

  defp upsert_pending_queue(repo, %Job{} = job) do
    scheduled_at = DateTime.truncate(job.scheduled_at, :second)

    on_conflict =
      from(pq in PendingQueue,
        update: [
          set: [next_runnable_at: fragment("LEAST(next_runnable_at, ?)", ^scheduled_at)]
        ]
      )

    %PendingQueue{}
    |> PendingQueue.changeset(%{
      scope: job.scope,
      queue: job.queue,
      next_runnable_at: scheduled_at
    })
    |> repo.insert!(upsert_opts(repo, on_conflict))
  end

  defp update_pending_queue_with_next_job!(repo, %Job{} = job) do
    %PendingQueue{}
    |> PendingQueue.changeset(%{
      scope: job.scope,
      queue: job.queue,
      next_runnable_at: next_runnable_at(job)
    })
    |> repo.insert!(upsert_opts(repo, set: [next_runnable_at: next_runnable_at(job)]))
  end

  defp upsert_opts(repo, on_conflict) do
    if repo.__adapter__() == Ecto.Adapters.MyXQL,
      do: [on_conflict: on_conflict],
      else: [on_conflict: on_conflict, conflict_target: [:scope, :queue]]
  end

  @doc false
  @spec refresh_pending_queue!(module, binary, binary) :: :ok
  def refresh_pending_queue!(repo, scope, queue) do
    case head_pending_job(repo, scope, queue) do
      nil ->
        delete_pending_queue(repo, scope, queue)

      %Job{} = job ->
        update_pending_queue_with_next_job!(repo, job)
    end

    :ok
  end

  defp delete_pending_queue(repo, scope, queue) do
    PendingQueue
    |> where([pq], pq.scope == ^scope and pq.queue == ^queue)
    |> repo.delete_all()
  end

  defp next_runnable_at(%Job{scheduled_at: scheduled_at, next_attempt_at: nil}),
    do: DateTime.truncate(scheduled_at, :second)

  defp next_runnable_at(%Job{scheduled_at: scheduled_at, next_attempt_at: next_attempt_at}),
    do: [scheduled_at, next_attempt_at] |> Enum.max(DateTime) |> DateTime.truncate(:second)

  defp head_pending_job(repo, scope, queue) do
    JobQueryable.queryable()
    |> JobQueryable.filter(scope: scope, queue: queue, available?: true)
    |> JobQueryable.order_by(asc: :scheduled_at, asc: :sequence)
    |> limit(1)
    |> repo.one()
  end

  @doc """
  Returns true if a job scheduled date is reached and the job is not done yet.
  Otherwise, returns false.
  """
  @spec processable_now?(Job.t()) :: boolean
  def processable_now?(%Job{} = job) do
    not done?(job) and not max_attempts_reached?(job) and runnable_now?(job)
  end

  @doc """
  Returns true if a job is done.
  Otherwise, returns false.
  """
  @spec done?(Job.t()) :: boolean
  def done?(%Job{} = job) do
    not is_nil(job.done_at)
  end

  @doc """
  Returns true if max job attempts is reached.
  Otherwise, returns false.
  """
  @spec max_attempts_reached?(Job.t()) :: boolean
  def max_attempts_reached?(%Job{} = job) do
    job.attempts >= job.max_attempts
  end

  @doc """
  Returns true if a job scheduled date is reached.
  Otherwise, returns false.
  """
  @spec runnable_now?(Job.t()) :: boolean
  def runnable_now?(%Job{} = job) do
    DateTime.compare(job.scheduled_at, DateTime.utc_now()) in [:eq, :lt] and
      (is_nil(job.next_attempt_at) or
         DateTime.compare(job.next_attempt_at, DateTime.utc_now()) in [:eq, :lt])
  end

  @doc """
  List the available pending queues by scope a.k.a by Queuetopia.

  The queues come from the queuetopia_pending_queues table.
  """
  @spec list_available_pending_queues(module, binary, keyword()) :: [binary]
  def list_available_pending_queues(repo, scope, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    PendingQueueQueryable.queryable()
    |> PendingQueueQueryable.filter(
      scope: scope,
      runnable_now?: true,
      without_locked_queues: scope
    )
    |> select([pq], pq.queue)
    |> query_limit(limit)
    |> repo.all()
  end

  defp query_limit(query, limit) when is_integer(limit),
    do: query |> limit(^limit) |> order_by(asc: fragment("RAND()"))

  defp query_limit(query, nil), do: query

  @doc """
  Get the next available pending job of a given queue by scope a.k.a by Queuetopia.
  If the queue is empty or the next pendign job is scheduled for later, returns nil.
  """
  @spec get_next_runnable_job(module, binary, binary) :: Job.t() | nil
  def get_next_runnable_job(repo, scope, queue) when is_binary(queue) do
    case head_pending_job(repo, scope, queue) do
      %Job{} = job -> if runnable_now?(job), do: job, else: nil
      _ -> nil
    end
  end

  @doc false
  @spec fetch_job(module, Job.t()) :: {:error, any} | {:ok, any}
  def fetch_job(repo, %Job{id: id} = job) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:lock, fn _, _ ->
      lock_queue(repo, job.scope, job.queue, job.timeout)
    end)
    |> Ecto.Multi.run(:job, fn _, _ ->
      job = repo.get(Job, id)

      with {:done?, false} <- {:done?, done?(job)},
           {:max_attempts_reached?, false} <-
             {:max_attempts_reached?, max_attempts_reached?(job)},
           {:runnable_now?, true} <- {:runnable_now?, runnable_now?(job)} do
        {:ok, job}
      else
        {:done?, true} -> {:error, "already done"}
        {:max_attempts_reached?, true} -> {:error, "max attempts reached"}
        {:runnable_now?, false} -> {:error, "scheduled for later"}
      end
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{job: job}} -> {:ok, job}
      {:error, :lock, _, _} -> {:error, :locked}
      {:error, :job, error, _} -> {:error, error}
    end
  end

  @doc false
  @spec perform(Job.t()) :: :ok | {:ok, any()} | {:error, binary}
  def perform(%Job{} = job) do
    performer = resolve_performer(job)
    performer.perform(job)
  end

  @doc false
  @spec persist_result!(module, Job.t(), {:error, any} | :ok | {:ok, any}) :: Job.t()

  def persist_result!(repo, %Job{} = job, {:ok, _res}), do: persist_success!(repo, job)
  def persist_result!(repo, %Job{} = job, :ok), do: persist_success!(repo, job)

  def persist_result!(repo, %Job{} = job, {:error, error}) when is_binary(error),
    do: persist_failure!(repo, job, error)

  def persist_result!(repo, %Job{} = job, unexpected_response),
    do: persist_failure!(repo, job, inspect(unexpected_response))

  defp persist_failure!(repo, %Job{} = job, error) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)
    performer = resolve_performer(job)
    backoff = performer.backoff(job)

    job
    |> Job.failed_job_changeset(%{
      attempts: job.attempts + 1,
      attempted_at: utc_now,
      attempted_by: Atom.to_string(Node.self()),
      next_attempt_at: utc_now |> DateTime.add(backoff, :millisecond),
      error: error
    })
    |> repo.update!()
    |> tap(&refresh_pending_queue!(repo, &1.scope, &1.queue))
    |> tap(&performer.handle_failed_job!/1)
  end

  defp persist_success!(repo, %Job{} = job) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    job
    |> Job.succeeded_job_changeset(%{
      attempts: job.attempts + 1,
      attempted_at: utc_now,
      attempted_by: Atom.to_string(Node.self()),
      done_at: utc_now
    })
    |> repo.update!()
    |> tap(&refresh_pending_queue!(repo, &1.scope, &1.queue))
  end

  defp resolve_performer(%Job{scope: scope}) do
    (String.split(scope, ".") ++ ["Performer"])
    |> Module.safe_concat()
  end

  @doc false
  @spec lock_queue(module, binary, binary, integer()) :: {:error, :locked} | {:ok, Lock.t()}
  def lock_queue(repo, scope, queue, timeout)
      when is_binary(queue) and is_integer(timeout) do
    utc_now = DateTime.utc_now()
    lock_retention = timeout + @lock_security_retention

    %Lock{}
    |> Lock.changeset(%{
      scope: scope,
      queue: queue,
      locked_at: utc_now,
      locked_by_node: Kernel.inspect(Node.self()),
      locked_until: DateTime.add(utc_now, lock_retention, :millisecond)
    })
    |> repo.insert()
    |> case do
      {:ok, %Lock{} = lock} -> {:ok, lock}
      {:error, _changeset} -> {:error, :locked}
    end
  end

  @doc false
  @spec release_expired_locks(module, binary) :: any()
  def release_expired_locks(repo, scope) do
    utc_now = DateTime.utc_now()

    Lock
    |> where([lock], lock.scope == ^scope)
    |> where([lock], lock.locked_until <= ^utc_now)
    |> repo.delete_all()
  end

  @doc false
  @spec unlock_queue(module, binary, binary) :: any
  def unlock_queue(repo, scope, queue) do
    Lock
    |> where([lock], lock.scope == ^scope)
    |> where([lock], lock.queue == ^queue)
    |> repo.delete_all()
  end

  @doc false
  def cleanup_completed_jobs(repo, scope, job_retention \\ {7, :day}) do
    {duration, unit} = job_retention
    cutoff_date = DateTime.utc_now() |> DateTime.add(-duration, unit)

    from(j in Job,
      where: j.scope == ^scope,
      where: not is_nil(j.done_at),
      where: j.done_at < ^cutoff_date
    )
    |> repo.delete_all()
  end
end
