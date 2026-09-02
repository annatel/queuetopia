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
    |> Ecto.Multi.run(:lock_pending_queue, fn repo, _ ->
      {:ok, PendingQueues.lock_pending_queue(repo, attrs[:scope], attrs[:queue])}
    end)
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
  @spec get_next_job(module, binary, binary) :: Job.t() | nil
  def get_next_job(repo, scope, queue) do
    JobQueryable.queryable()
    |> JobQueryable.filter(scope: scope, queue: queue, available?: true)
    |> JobQueryable.order_by(asc: :scheduled_at, asc: :sequence)
    |> limit(1)
    |> repo.one()
  end

  defp performable_now?(%Job{} = job) do
    not done?(job) and not max_attempts_reached?(job) and scheduled_date_reached?(job)
  end

  @doc false
  @spec next_performable_at(Job.t()) :: DateTime.t()
  def next_performable_at(%Job{scheduled_at: scheduled_at, next_attempt_at: nil}),
    do: DateTime.truncate(scheduled_at, :second)

  def next_performable_at(%Job{scheduled_at: scheduled_at, next_attempt_at: next_attempt_at}),
    do: [scheduled_at, next_attempt_at] |> Enum.max(DateTime) |> DateTime.truncate(:second)

  defp done?(%Job{} = job), do: not is_nil(job.done_at)

  defp max_attempts_reached?(%Job{} = job), do: job.attempts >= job.max_attempts

  defp scheduled_date_reached?(%Job{} = job) do
    DateTime.compare(job.scheduled_at, DateTime.utc_now()) in [:eq, :lt] and
      (is_nil(job.next_attempt_at) or
         DateTime.compare(job.next_attempt_at, DateTime.utc_now()) in [:eq, :lt])
  end

  @doc false
  @spec acquire_next_performable_job(module, binary, binary) ::
          {:ok, Job.t()} | {:error, :locked | :no_performable_job}
  def acquire_next_performable_job(repo, scope, queue) do
    {:ok, result} =
      repo.transaction(fn ->
        PendingQueues.lock_pending_queue(repo, scope, queue)

        with %Job{} = job <- get_next_job(repo, scope, queue),
             true <- performable_now?(job),
             {:ok, _lock} <- Locks.lock_queue(repo, scope, queue, job.timeout) do
          {:ok, job}
        else
          {:error, :locked} -> {:error, :locked}
          _ -> {:error, :no_performable_job}
        end
      end)

    result
  end

  @doc false
  @spec perform(Job.t()) :: :ok | {:ok, any()} | {:error, binary}
  def perform(%Job{} = job) do
    performer = resolve_performer(job)
    performer.perform(job)
  end

  @doc false
  @spec persist_result!(module, Job.t(), {:error, any} | :ok | {:ok, any}) :: Job.t()

  def persist_result!(repo, %Job{} = job, result) do
    case normalize_result(result) do
      :success -> persist_success!(repo, job)
      {:failure, error} -> persist_failure!(repo, job, error)
    end
  end

  defp normalize_result(:ok), do: :success
  defp normalize_result({:ok, _res}), do: :success
  defp normalize_result({:error, error}) when is_binary(error), do: {:failure, error}
  defp normalize_result(unexpected_response), do: {:failure, inspect(unexpected_response)}

  defp persist_success!(repo, %Job{} = job) do
    attrs = attempt_attrs(job)

    job
    |> Job.succeeded_job_changeset(Map.put(attrs, :done_at, attrs.attempted_at))
    |> update_job_and_refresh_pending_queue!(repo)
  end

  defp persist_failure!(repo, %Job{} = job, error) do
    performer = resolve_performer(job)
    attrs = attempt_attrs(job)

    job
    |> Job.failed_job_changeset(
      Map.merge(attrs, %{
        next_attempt_at: DateTime.add(attrs.attempted_at, performer.backoff(job), :millisecond),
        error: error
      })
    )
    |> update_job_and_refresh_pending_queue!(repo)
    |> tap(&performer.handle_failed_job!/1)
  end

  defp attempt_attrs(%Job{} = job) do
    %{
      attempts: job.attempts + 1,
      attempted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      attempted_by: Atom.to_string(Node.self())
    }
  end

  defp update_job_and_refresh_pending_queue!(changeset, repo) do
    changeset
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

    JobQueryable.queryable()
    |> JobQueryable.filter(scope: scope, done_before: cutoff_date)
    |> repo.delete_all()
  end
end
