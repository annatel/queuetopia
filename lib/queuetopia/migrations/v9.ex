defmodule Queuetopia.Migrations.V9 do
  @moduledoc false

  use Ecto.Migration

  @index_name "queuetopia_pending_queues_performable_index"

  def up do
    unless index_exists?() do
      create(
        index(:queuetopia_pending_queues, [:scope, :next_performable_at, :queue],
          name: @index_name
        )
      )
    end
  end

  def down do
    if index_exists?() do
      drop(
        index(:queuetopia_pending_queues, [:scope, :next_performable_at, :queue],
          name: @index_name
        )
      )
    end
  end

  defp index_exists?() do
    %{num_rows: num_rows} =
      repo().query!("""
      SELECT 1 FROM information_schema.statistics
      WHERE table_schema = DATABASE()
        AND table_name = 'queuetopia_pending_queues'
        AND index_name = '#{@index_name}'
      LIMIT 1
      """)

    num_rows > 0
  end
end
