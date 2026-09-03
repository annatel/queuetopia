defmodule Queuetopia.Locks.LockQueryable do
  use AntlUtilsEcto.Queryable,
    base_schema: Queuetopia.Locks.Lock

  import Ecto.Query

  @filterable_fields ~w(scope queue expired?)a

  defp filter_by_field(queryable, {:expired?, true}) do
    queryable |> where([lock], lock.locked_until <= ^DateTime.utc_now())
  end

  defp filter_by_field(_queryable, {key, _value}) when key not in @filterable_fields do
    raise ArgumentError, "Filter not implemented"
  end
end
