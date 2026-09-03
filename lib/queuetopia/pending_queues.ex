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
          set: [next_performable_at: fragment("LEAST(next_performable_at, ?)", ^scheduled_at)]
        ]
      )

    %PendingQueue{}
    |> PendingQueue.changeset(%{
      scope: job.scope,
      queue: job.queue,
      next_performable_at: scheduled_at
    })
    |> repo.insert!(on_conflict: on_conflict)
  end

  defp update_pending_queue!(repo, %Job{} = job) do
    %PendingQueue{}
    |> PendingQueue.changeset(%{
      scope: job.scope,
      queue: job.queue,
      next_performable_at: Jobs.next_performable_at(job)
    })
    |> repo.insert!(on_conflict: [set: [next_performable_at: Jobs.next_performable_at(job)]])
  end

  @doc false
  @spec refresh_pending_queue!(module, binary, binary) :: :ok
  def refresh_pending_queue!(repo, scope, queue) do
    {:ok, :ok} =
      repo.transaction(fn ->
        lock_pending_queue(repo, scope, queue)

        case Jobs.get_next_job(repo, scope, queue) do
          %Job{} = job -> update_pending_queue!(repo, job)
          nil -> delete_pending_queue(repo, scope, queue)
        end

        :ok
      end)

    :ok
  end

  @doc false
  def lock_pending_queue(repo, scope, queue) do
    PendingQueueQueryable.queryable()
    |> PendingQueueQueryable.filter(scope: scope, queue: queue)
    |> lock("FOR UPDATE NOWAIT")
    |> repo.one()
  end

  defp delete_pending_queue(repo, scope, queue) do
    PendingQueueQueryable.queryable()
    |> PendingQueueQueryable.filter(scope: scope, queue: queue)
    |> repo.delete_all()
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
