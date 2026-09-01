defmodule Queuetopia.PendingQueues do
  @moduledoc false

  import Ecto.Query

  alias Queuetopia.Jobs
  alias Queuetopia.Jobs.Job
  alias Queuetopia.PendingQueues.PendingQueue
  alias Queuetopia.PendingQueues.PendingQueueQueryable

  @doc false
  @spec upsert_pending_queue(module, Job.t()) :: PendingQueue.t()
  def upsert_pending_queue(repo, %Job{} = job) do
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

  defp update_pending_queue!(repo, %Job{} = job) do
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
    case Jobs.head_pending_job(repo, scope, queue) do
      nil ->
        delete_pending_queue(repo, scope, queue)

      %Job{} = job ->
        update_pending_queue!(repo, job)
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
      ready?: true,
      without_locked_queues: scope
    )
    |> select([pq], pq.queue)
    |> query_limit(limit)
    |> repo.all()
  end

  defp query_limit(query, limit) when is_integer(limit),
    do: query |> limit(^limit) |> order_by(asc: fragment("RAND()"))

  defp query_limit(query, nil), do: query
end
