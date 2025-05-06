defmodule Queuetopia.Queue.JobQueryable do
  use AntlUtilsEcto.Queryable,
    base_schema: Queuetopia.Queue.Job,
    searchable_fields: [:scope, :queue, :action, :params]

  import Ecto.Query

  @filterable_fields ~w(id scope queue action available?)a

  defp filter_by_field(queryable, {:available?, true}) do
    queryable
    |> where([job], is_nil(job.ended_at))
  end

  defp filter_by_field(_queryable, {key, _value}) when key not in @filterable_fields do
    raise ArgumentError, "Filter not implemented"
  end
end
