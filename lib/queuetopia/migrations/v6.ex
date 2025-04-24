defmodule Queuetopia.Migrations.V6 do
  @moduledoc false

  use Ecto.Migration

  def up do
    rename(table(:queuetopia_jobs), :done_at, to: :ended_at)
    rename(index(:queuetopia_jobs, [:ended_at], name: "queuetopia_jobs_done_at_index"), to: "queuetopia_jobs_ended_at_index")

    alter table(:queuetopia_jobs) do
      add(:end_status, :string, null: true)
    end
  end

  def down do
    rename(table(:queuetopia_jobs), :ended_at, to: :done_at)
    rename(index(:queuetopia_jobs, [:done_at], name: "queuetopia_jobs_ended_at_index"), to: "queuetopia_jobs_done_at_index")

    alter table(:queuetopia_jobs) do
      remove(:end_status)
    end
  end
end
