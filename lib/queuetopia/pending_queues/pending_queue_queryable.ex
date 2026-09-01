defmodule Queuetopia.PendingQueues.PendingQueueQueryable do
  use AntlUtilsEcto.Queryable,
    base_schema: Queuetopia.PendingQueues.PendingQueue

  import Ecto.Query

  alias Queuetopia.Locks.Lock

  @filterable_fields ~w(scope queue ready? without_locked_queues)a

  defp filter_by_field(queryable, {:ready?, true}) do
    queryable |> where([pq], pq.next_runnable_at <= ^DateTime.utc_now())
  end

  defp filter_by_field(queryable, {:without_locked_queues, scope}) do
    locked_queues =
      Lock
      |> select([:queue])
      |> where([l], l.scope == ^scope)

    queryable |> where([pq], pq.queue not in subquery(locked_queues))
  end

  defp filter_by_field(_queryable, {key, _value}) when key not in @filterable_fields do
    raise ArgumentError, "Filter not implemented"
  end
end
