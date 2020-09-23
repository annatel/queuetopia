defmodule Queuetopia.Jobs do
  import Ecto.Query
  alias Ecto.Multi

  alias Queuetopia.Sequences
  alias Queuetopia.Locks
  alias Queuetopia.Locks.Lock
  alias Queuetopia.Jobs.Job
  alias AntlUtilsElixir.Math

  @doc """
  List the available pending queues by scope a.k.a by Queuetopia.
  """
  @spec list_available_pending_queues(module(), binary()) :: [binary()]
  def list_available_pending_queues(repo, scope) do
    subset =
      Lock
      |> select([:queue])
      |> where([l], l.scope == ^scope)

    Job
    |> where([j], is_nil(j.done_at))
    |> where([j], j.scope == ^scope)
    |> where([j], j.queue not in subquery(subset))
    |> select([:queue])
    |> distinct(true)
    |> repo.all()
    |> Enum.map(& &1.queue)
  end

  @doc """
  Get the next available pending job of a given queue by scope a.k.a by Queuetopia.
  If the queue is empty or the next pendign job is scheduled for later, returns nil.
  """
  @spec get_next_pending_job(module(), binary(), binary()) :: Job.t() | nil
  def get_next_pending_job(repo, scope, queue) when is_binary(queue) do
    job =
      Job
      |> where([j], j.queue == ^queue)
      |> where([j], j.scope == ^scope)
      |> where([j], is_nil(j.done_at))
      |> order_by(asc: :sequence)
      |> limit(1)
      |> repo.one()

    case job do
      %Job{} -> if scheduled_for_now?(job), do: job, else: nil
      _ -> nil
    end
  end

  @doc """
  Fetches a specific job. Acquires the lock on the queue and returns the job if it actually and reached it schedule time.
  In case of error, returns a tuple error.
  """
  @spec fetch_job(module(), Job.t()) :: {:error, any} | {:ok, any}
  def fetch_job(repo, %Job{id: id} = job) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:lock, fn _, _ ->
      Locks.lock_queue(repo, job.scope, job.queue, job.timeout)
    end)
    |> Ecto.Multi.run(:job, fn _, _ ->
      job = repo.get(Job, id)

      with {:done?, false} <- {:done?, done?(job)},
           {:scheduled_for_now?, true} <- {:scheduled_for_now?, scheduled_for_now?(job)} do
        {:ok, job}
      else
        {:done?, true} -> {:error, "already done"}
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

  @doc """
  Creates a job, specifying the performer, the Queuetopia (scope), and the user params,
  including options.
  """

  @spec create_job(module(), binary(), binary(), binary(), binary(), map(), [Job.option()]) ::
          {:error, Ecto.Changeset.t()} | {:ok, Job.t()}

  def create_job(repo, performer, scope, queue, action, params, opts \\ []) do
    options = Enum.into(opts, %{})

    %{
      scope: scope,
      queue: queue,
      performer: performer,
      action: action,
      params: params,
      scheduled_at: DateTime.utc_now()
    }
    |> Map.merge(options)
    |> create_job_multi()
    |> repo.transaction()
    |> case do
      {:ok, %{job: job}} -> {:ok, job}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  defp create_job_multi(attrs) do
    Multi.new()
    |> Multi.run(:sequence, fn repo, %{} ->
      {:ok, Sequences.next(:queuetopia_sequences, repo)}
    end)
    |> Multi.insert(:job, fn %{sequence: sequence} ->
      Job.create_changeset(attrs |> Map.put(:sequence, sequence))
    end)
  end

  @doc """
  Performs the job. Let the performer do its job.
  """
  @spec perform(Job.t()) :: :ok | {:ok, any()} | {:error, binary()}
  def perform(%Job{} = job) do
    performer = resolve_performer(job)
    performer.perform(job)
  end

  @doc """
  Persist in DB the result of job execution.
  Attempts fields are filled.
  In case of success, set the done_at field.
  Otherwise, save the error, prepare the job for a next retry, resetting the scheduled_at with the backoff calculation.
  """
  @spec persist_result(module(), Job.t(), {:error, any} | :ok | {:ok, any}) :: Job.t()
  def persist_result(repo, %Job{} = job, {:error, error}) when is_binary(error),
    do: persist_failure(repo, job, error)

  def persist_result(repo, %Job{} = job, {:ok, _res}),
    do: persist_success(repo, job)

  def persist_result(repo, %Job{} = job, :ok),
    do: persist_success(repo, job)

  defp persist_failure(repo, %Job{} = job, error) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)
    backoff = exponential_backoff(job.attempts, job.max_backoff)

    job
    |> Job.failed_job_changeset(%{
      attempts: job.attempts + 1,
      attempted_at: utc_now,
      attempted_by: Atom.to_string(Node.self()),
      scheduled_at: utc_now |> DateTime.add(backoff, :millisecond),
      error: error
    })
    |> repo.update()
  end

  defp persist_success(repo, %Job{} = job) do
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    job
    |> Job.succeeded_job_changeset(%{
      attempts: job.attempts + 1,
      attempted_at: utc_now,
      attempted_by: Atom.to_string(Node.self()),
      done_at: utc_now
    })
    |> repo.update()
  end

  defp exponential_backoff(iteration, max_backoff) do
    backoff = ((Math.pow(2, iteration) |> round) + 1) * 1_000
    min(backoff, max_backoff)
  end

  defp resolve_performer(%Job{performer: performer}) do
    performer
    |> String.split(".")
    |> Module.safe_concat()
  end

  @doc """
  Returns true if a job scheduled date is reached and the job is not done yet.
  Otherwise, returns false.
  """
  @spec processable_now?(Job.t()) :: boolean
  def processable_now?(%Job{} = job) do
    not done?(job) and scheduled_for_now?(job)
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
  Returns true if a job scheduled date is reached.
  Otherwise, returns false.
  """
  @spec scheduled_for_now?(Job.t()) :: boolean
  def scheduled_for_now?(%Job{} = job) do
    is_nil(job.scheduled_at) ||
      DateTime.compare(DateTime.utc_now(), job.scheduled_at) in [:eq, :gt]
  end
end
