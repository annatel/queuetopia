defmodule Queuetopia.Jobs.JobQueryable do
  use AntlUtilsEcto.Queryable,
    base_schema: Queuetopia.Jobs.Job,
    searchable_fields: [:scope, :queue, :action, :params]

  import Ecto.Query

  @filterable_fields ~w(id scope queue action available? done_before)a

  defp filter_by_field(queryable, {:available?, true}) do
    queryable
    |> where([job], is_nil(job.done_at))
    |> where([job], job.attempts < job.max_attempts)
  end

  defp filter_by_field(queryable, {:done_before, %DateTime{} = cutoff_date}) do
    queryable
    |> where([job], not is_nil(job.done_at))
    |> where([job], job.done_at < ^cutoff_date)
  end

  defp filter_by_field(_queryable, {key, _value}) when key not in @filterable_fields do
    raise ArgumentError, "Filter not implemented"
  end
end
