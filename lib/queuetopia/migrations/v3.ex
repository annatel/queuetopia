defmodule Queuetopia.Migrations.V3 do
  @moduledoc false

  use Ecto.Migration

  def up do
    execute("ALTER TABLE queuetopia_jobs ADD COLUMN next_attempt_at datetime AFTER attempted_by;")
  end

  def down do
    alter table("queuetopia_jobs") do
      remove(:next_attempt_at)
    end
  end
end
