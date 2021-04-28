defmodule Queuetopia.Migrations.V3 do
  @moduledoc false

  use Ecto.Migration

  def up do
    case repo().__adapter__() do
      Ecto.Adapters.Postgres ->
        execute("ALTER TABLE queuetopia_jobs ADD COLUMN next_attempt_at timestamp;")

      Ecto.Adapters.MyXQL ->
        execute(
          "ALTER TABLE queuetopia_jobs ADD COLUMN next_attempt_at datetime AFTER attempted_by;"
        )
    end
  end

  def down do
    alter table("queuetopia_jobs") do
      remove(:next_attempt_at)
    end
  end
end
