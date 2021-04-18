defmodule Queuetopia.Migrations.Helper do
  @moduledoc false

  use Ecto.Migration

  def create_index_if_not_exists(table, columns, opts \\ []) do
    index = struct(%Ecto.Migration.Index{table: table, columns: columns}, opts)
    index_name = (index.name || default_index_name(index)) |> to_string()

    flush()
    query = "SHOW INDEX FROM #{table};"
    %{rows: indexes} = Ecto.Adapters.SQL.query!(repo(), query, [])

    indexes
    |> Enum.map(fn [_, _, index_name | _t] -> index_name end)
    |> Enum.member?(index_name)
    |> unless do
      create(index(table, columns, opts))
    end
  end

  defp default_index_name(index) do
    [index.table, index.columns, "index"]
    |> List.flatten()
    |> Enum.map(&to_string(&1))
    |> Enum.map(&String.replace(&1, ~r"[^\w_]", "_"))
    |> Enum.map(&String.replace_trailing(&1, "_", ""))
    |> Enum.join("_")
    |> String.to_atom()
  end
end
