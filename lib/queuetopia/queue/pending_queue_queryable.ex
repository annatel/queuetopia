defmodule Queuetopia.Queue.PendingQueueQueryable do
  use AntlUtilsEcto.Queryable,
    base_schema: Queuetopia.Queue.PendingQueue

  import Ecto.Query

  alias Queuetopia.Queue.Lock

  @filterable_fields ~w(scope queue runnable_now? without_locked_queues)a

  defp filter_by_field(queryable, {:runnable_now?, true}) do
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
