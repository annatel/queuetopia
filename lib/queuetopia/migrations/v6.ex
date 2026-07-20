defmodule Queuetopia.Migrations.V6 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create(
      index(
        :queuetopia_jobs,
        [:scope, :done_at, :scheduled_at, :next_attempt_at, :queue, :attempts, :max_attempts],
        name: :queuetopia_jobs_pending_queues_index
      )
    )

    create(
      index(
        :queuetopia_jobs,
        [:scope, :queue, :done_at, :scheduled_at, :sequence],
        name: :queuetopia_jobs_next_pending_job_index
      )
    )
  end

  def down do
    drop(index(:queuetopia_jobs, [], name: :queuetopia_jobs_pending_queues_index))
    drop(index(:queuetopia_jobs, [], name: :queuetopia_jobs_next_pending_job_index))
  end
end
