defmodule Queuetopia.Migrations.V10 do
  @moduledoc false

  use Ecto.Migration

  def up do
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
    ON DUPLICATE KEY UPDATE
      next_performable_at = LEAST(next_performable_at, VALUES(next_performable_at)),
      updated_at = UTC_TIMESTAMP()
    """)
  end

  def down do
    :ok
  end
end
