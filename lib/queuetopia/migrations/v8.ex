defmodule Queuetopia.Migrations.V8 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create_if_not_exists table(:queuetopia_pending_queues, primary_key: false) do
      add(:scope, :string, null: false, primary_key: true)
      add(:queue, :string, null: false, primary_key: true)
      add(:next_performable_at, :utc_datetime, null: false)

      timestamps()
    end
  end

  def down do
    drop_if_exists(table(:queuetopia_pending_queues))
  end
end
