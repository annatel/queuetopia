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

    create(
      index(:queuetopia_pending_queues, [:scope, :next_performable_at, :queue],
        name: :queuetopia_pending_queues_performable_index
      )
    )

    execute("""
    INSERT INTO queuetopia_pending_queues (scope, queue, next_performable_at, inserted_at, updated_at)
    SELECT scope,
           queue,
           MIN(GREATEST(scheduled_at, COALESCE(next_attempt_at, scheduled_at))),
           UTC_TIMESTAMP(),
           UTC_TIMESTAMP()
    FROM queuetopia_jobs
    WHERE done_at IS NULL AND attempts < max_attempts
    GROUP BY scope, queue
    """)
  end

  def down do
    drop_if_exists(table(:queuetopia_pending_queues))
  end
end
