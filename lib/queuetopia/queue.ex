defmodule Queuetopia.Queue do
  @moduledoc false

  import Ecto.Query

  alias Queuetopia.Queue.{Job, Lock}
  alias Queuetopia.Queue.JobQueryable

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
  Creates a job, specifying the performer, the Queuetopia (scope), and the user params,
  including options.
  """

  @spec create_job(map, module) :: {:error, Ecto.Changeset.t()} | {:ok, Job.t()}
  def create_job(attrs, repo) do
    attrs
    |> Job.create_changeset()
    |> repo.insert()
  end

  @doc """
  Returns true if a job scheduled date is reached and the job is not ended yet.
  Otherwise, returns false.
  """
  @spec processable_now?(Job.t()) :: boolean
  def processable_now?(%Job{} = job) do
    not ended?(job) and scheduled_for_now?(job)
  end

  @doc """
  Returns true if a job is successfully ended.
  Otherwise, returns false.
  """
  @spec done?(Job.t()) :: boolean
  def done?(%Job{} = job) do
    ended?(job) and job.end_status == "success"
  end

  @doc """
  Returns true if a job is somehow ended.
  Otherwise, returns false.
  """
  @spec ended?(Job.t()) :: boolean
  def ended?(%Job{} = job) do
    not is_nil(job.ended_at)
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
  @spec scheduled_for_now?(Job.t()) :: boolean
  def scheduled_for_now?(%Job{} = job) do
    DateTime.compare(job.scheduled_at, DateTime.utc_now()) in [:eq, :lt] and
      (is_nil(job.next_attempt_at) or
         DateTime.compare(job.next_attempt_at, DateTime.utc_now()) in [:eq, :lt])
  end

  @doc """
  List the available pending queues by scope a.k.a by Queuetopia.
  """
  @spec list_available_pending_queues(module, binary, keyword()) :: [binary]
  def list_available_pending_queues(repo, scope, opts \\ []) do
    utc_now = DateTime.utc_now()

    locked_queues =
      Lock
      |> select([:queue])
      |> where([l], l.scope == ^scope)

    blocked_queues =
      Job
      |> select([:queue])
      |> where([j], j.scope == ^scope)
      |> where([j], is_nil(j.ended_at))
      |> where([j], j.scheduled_at <= ^utc_now and j.next_attempt_at > ^utc_now)

    where_immediately_executable_job = fn queryable ->
      queryable
      |> where(
        [j],
        j.scheduled_at <= ^utc_now and
          (is_nil(j.next_attempt_at) or j.next_attempt_at <= ^utc_now)
      )
    end

    limit = Keyword.get(opts, :limit)

    query =
      Job
      |> where([j], j.scope == ^scope)
      |> where([j], is_nil(j.ended_at))
      |> where([j], j.queue not in subquery(locked_queues))
      |> where([j], j.queue not in subquery(blocked_queues))
      |> where_immediately_executable_job.()
      |> select([:queue])
      |> distinct(true)
      |> then(&query_limit(&1, limit))

    repo.all(query) |> Enum.map(& &1.queue)
  end

  defp query_limit(query, limit) when is_integer(limit),
    do: query |> limit(^limit) |> order_by(asc: fragment("RAND()"))

  defp query_limit(query, nil), do: query

  @doc """
  Get the next available pending job of a given queue by scope a.k.a by Queuetopia.
  If the queue is empty or the next pendign job is scheduled for later, returns nil.
  """
  @spec get_next_pending_job(module, binary, binary) :: Job.t() | nil
  def get_next_pending_job(repo, scope, queue) when is_binary(queue) do
    job =
      Job
      |> where([j], j.queue == ^queue)
      |> where([j], j.scope == ^scope)
      |> where([j], is_nil(j.ended_at))
      |> order_by(asc: :scheduled_at, asc: :sequence)
      |> limit(1)
      |> repo.one()

    case job do
      %Job{} -> if scheduled_for_now?(job), do: job, else: nil
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

      with {:ended?, false} <- {:ended?, ended?(job)},
           {:scheduled_for_now?, true} <- {:scheduled_for_now?, scheduled_for_now?(job)} do
        {:ok, job}
      else
        {:ended?, true} -> {:error, "already ended"}
        {:scheduled_for_now?, false} -> {:error, "scheduled for later"}
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
  @spec persist_result!(module, Job.t(), {:error, any} | :ok | {:ok, any} | :aborted) :: Job.t()

  def persist_result!(repo, %Job{} = job, {:ok, _res}), do: persist_success!(repo, job)
  def persist_result!(repo, %Job{} = job, :ok), do: persist_success!(repo, job)

  def persist_result!(repo, %Job{} = job, :aborted),
    do: persist_abort!(repo, job)

  def persist_result!(repo, %Job{} = job, {:error, error}) when is_binary(error),
    do: persist_failure!(repo, job, error)

  def persist_result!(repo, %Job{} = job, unexpected_response),
    do: persist_failure!(repo, job, inspect(unexpected_response))

  defp persist_failure!(repo, %Job{attempts: attempts, max_attempts: max_attempts} = job, error)
       when attempts + 1 >= max_attempts do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)
    performer = resolve_performer(job)

    job
    |> Job.failed_job_changeset(%{
      attempts: job.attempts + 1,
      attempted_at: utc_now,
      attempted_by: Atom.to_string(Node.self()),
      ended_at: utc_now,
      end_status: "max_attempts_reached",
      error: error
    })
    |> repo.update!()
    |> tap(&performer.handle_failed_job!/1)
  end

  defp persist_failure!(repo, %Job{} = job, error) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)
    performer = resolve_performer(job)
    backoff = performer.backoff(job)

    job
    |> Job.retry_job_changeset(%{
      attempts: job.attempts + 1,
      attempted_at: utc_now,
      attempted_by: Atom.to_string(Node.self()),
      next_attempt_at: utc_now |> DateTime.add(backoff, :millisecond),
      error: error
    })
    |> repo.update!()
    |> tap(&performer.handle_failed_job!/1)
  end

  defp persist_abort!(repo, %Job{} = job) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    job
    |> Job.aborted_job_changeset(%{
      ended_at: utc_now
    })
    |> repo.update!()
  end

  defp persist_success!(repo, %Job{} = job) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    job
    |> Job.succeeded_job_changeset(%{
      attempts: job.attempts + 1,
      attempted_at: utc_now,
      attempted_by: Atom.to_string(Node.self()),
      ended_at: utc_now
    })
    |> repo.update!()
  end

  defp resolve_performer(%Job{performer: performer}) do
    performer
    |> String.split(".")
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
end
