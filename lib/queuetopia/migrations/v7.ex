defmodule Queuetopia.Migrations.V7 do
  @moduledoc false

  use Ecto.Migration

  def up do
    alter(table(:queuetopia_jobs)) do
      remove(:performer)
    end
  end

  def down do
    alter(table(:queuetopia_jobs)) do
      add(:performer, :string)
    end
  end
end
