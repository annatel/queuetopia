defmodule Queuetopia.Migrations.V1 do
  @moduledoc false

  use Ecto.Migration
  alias Queuetopia.Migrations.Helper

  def up do
    create_sequences_table()
    create_locks_table()
    create_jobs_table()
  end

  def down do
    drop_sequences_table()
    drop_locks_table()
    drop_jobs_table()
  end

  defp create_sequences_table do
    create_if_not_exists table(:queuetopia_sequences) do
      add(:sequence, :integer)

      timestamps()
    end

    Helper.create_index_if_not_exists(:queuetopia_sequences, [:sequence])

    utc_now = DateTime.utc_now() |> DateTime.to_naive()

    repo().query!(
      "INSERT into queuetopia_sequences(`sequence`, `inserted_at`, `updated_at`) VALUE (0, '#{
        utc_now
      }', '#{utc_now}');"
    )
  end

  defp drop_sequences_table do
    drop(table(:queuetopia_sequences))
  end

  defp create_locks_table do
    create_if_not_exists table(:queuetopia_locks, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:scope, :string, null: false)
      add(:queue, :string, null: false)
      add(:locked_at, :utc_datetime, null: true)
      add(:locked_by_node, :string, null: true)
      add(:locked_until, :utc_datetime, null: true)

      timestamps()
    end

    Helper.create_index_if_not_exists(:queuetopia_locks, [:scope, :queue],
      name: :queuetopia_locks_scope_queue_index,
      unique: true
    )
  end

  defp drop_locks_table do
    drop(table(:queuetopia_locks))
  end

  defp create_jobs_table() do
    create_if_not_exists table(:queuetopia_jobs, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:sequence, :integer, null: false)
      add(:scope, :string, null: false)
      add(:queue, :string, null: false)
      add(:performer, :string, null: false)
      add(:action, :string, null: false)
      add(:params, :map, null: false)
      add(:timeout, :integer, null: false)
      add(:max_backoff, :integer, null: false)
      add(:max_attempts, :integer, null: false)

      add(:scheduled_at, :utc_datetime, null: false)
      add(:attempts, :integer, null: false, default: 0)
      add(:attempted_at, :utc_datetime, null: true)
      add(:attempted_by, :string, null: true)
      add(:done_at, :utc_datetime, null: true)
      add(:error, :text, null: true)

      timestamps()
    end

    Helper.create_index_if_not_exists(:queuetopia_jobs, [:sequence])

    Helper.create_index_if_not_exists(:queuetopia_jobs, [:scope, :queue],
      name: :queuetopia_jobs_scope_queue_index
    )

    Helper.create_index_if_not_exists(:queuetopia_jobs, [:scheduled_at])
    Helper.create_index_if_not_exists(:queuetopia_jobs, [:done_at])
  end

  defp drop_jobs_table do
    drop(table(:queuetopia_jobs))
  end
end
