defmodule Queuetopia.Migrations.V6 do
  @moduledoc false

  use Ecto.Migration

  def up do
    rename(table(:queuetopia_jobs), :done_at, to: :ended_at)

    rename(index(:queuetopia_jobs, [:ended_at], name: "queuetopia_jobs_done_at_index"),
      to: "queuetopia_jobs_ended_at_index"
    )

    alter table(:queuetopia_jobs) do
      add(:end_status, :string, null: true)
    end

    max_attempts_reached =
      """
      UPDATE queuetopia_jobs
      SET ended_at = attempted_at
      WHERE ended_at IS NULL AND attempts >= max_attempts;
      """

    execute(max_attempts_reached)

    end_status_query =
      """
      UPDATE queuetopia_jobs
      SET end_status =
        CASE
          WHEN error IS NULL THEN 'success'
          ELSE 'failed'
        END
      WHERE ended_at IS NOT NULL;
      """

    execute(end_status_query)
  end

  def down do
    rename(table(:queuetopia_jobs), :ended_at, to: :done_at)

    rename(index(:queuetopia_jobs, [:done_at], name: "queuetopia_jobs_ended_at_index"),
      to: "queuetopia_jobs_done_at_index"
    )

    alter table(:queuetopia_jobs) do
      remove(:end_status)
    end
  end
end
