defmodule Queuetopia.Migrations.V3 do
  @moduledoc false

  use Ecto.Migration

  def up do
    query =
      case repo().__adapter__() do
        Ecto.Adapters.Postgres ->
          "ALTER TABLE queuetopia_jobs ADD COLUMN next_attempt_at timestamp;"

        Ecto.Adapters.MyXQL ->
          "ALTER TABLE queuetopia_jobs ADD COLUMN next_attempt_at datetime AFTER attempted_by;"
      end

    execute(query)
  end

  def down do
    alter table("queuetopia_jobs") do
      remove(:next_attempt_at)
    end
  end
end
