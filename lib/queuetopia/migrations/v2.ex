defmodule Queuetopia.Migrations.V2 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create(index(:queuetopia_jobs, [:scheduled_at, :sequence]))
  end

  def down do
    :noop
  end
end
