defmodule Queuetopia.Jobs do
  @moduledoc false

  import Ecto.Query

  alias Queuetopia.Jobs.Job
  alias Queuetopia.Locks
  alias Queuetopia.PendingQueues
  alias Queuetopia.Jobs.JobQueryable

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
      {:ok, PendingQueues.upsert_pending_queue(repo, job)}
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{job: job}} -> {:ok, job}
      {:error, :job, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
    end
  end

  @doc false
  @spec head_pending_job(module, binary, binary) :: Job.t() | nil
  def head_pending_job(repo, scope, queue) do
    JobQueryable.queryable()
    |> JobQueryable.filter(scope: scope, queue: queue, available?: true)
    |> JobQueryable.order_by(asc: :scheduled_at, asc: :sequence)
    |> limit(1)
    |> repo.one()
  end

  defp runnable_now?(%Job{} = job) do
    not done?(job) and not max_attempts_reached?(job) and scheduled_date_reached?(job)
  end

  defp done?(%Job{} = job) do
    not is_nil(job.done_at)
  end

  defp max_attempts_reached?(%Job{} = job) do
    job.attempts >= job.max_attempts
  end

  defp scheduled_date_reached?(%Job{} = job) do
    DateTime.compare(job.scheduled_at, DateTime.utc_now()) in [:eq, :lt] and
      (is_nil(job.next_attempt_at) or
         DateTime.compare(job.next_attempt_at, DateTime.utc_now()) in [:eq, :lt])
  end

  @doc """
  Get the next runnable job of a given queue by scope a.k.a by Queuetopia.
  If the queue is empty or the next pending job is scheduled for later, returns nil.
  """
  @spec get_next_runnable_job(module, binary, binary) :: Job.t() | nil
  def get_next_runnable_job(repo, scope, queue) when is_binary(queue) do
    case head_pending_job(repo, scope, queue) do
      %Job{} = job -> if runnable_now?(job), do: job, else: nil
      _ -> nil
    end
  end

  @doc false
  @spec claim_next_runnable_job(module, binary, binary) ::
          {:ok, Job.t()} | {:error, :locked | :no_runnable_job | :stale_job}
  def claim_next_runnable_job(repo, scope, queue) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:head, fn _, _ ->
      case get_next_runnable_job(repo, scope, queue) do
        %Job{} = job -> {:ok, job}
        nil -> {:error, :no_runnable_job}
      end
    end)
    |> Ecto.Multi.run(:lock, fn _, %{head: head} ->
      Locks.lock_queue(repo, scope, queue, head.timeout)
    end)
    |> Ecto.Multi.run(:job, fn _, %{head: head} ->
      job = repo.get(Job, head.id)

      if runnable_now?(job), do: {:ok, job}, else: {:error, :stale_job}
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{job: job}} -> {:ok, job}
      {:error, :head, error, _} -> {:error, error}
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
    |> tap(&PendingQueues.refresh_pending_queue!(repo, &1.scope, &1.queue))
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
    |> tap(&PendingQueues.refresh_pending_queue!(repo, &1.scope, &1.queue))
  end

  defp resolve_performer(%Job{scope: scope}) do
    (String.split(scope, ".") ++ ["Performer"])
    |> Module.safe_concat()
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
