defmodule Queuetopia.Migrations.V5 do
  @moduledoc false

  use Ecto.Migration

  def up do
    create(index(:queuetopia_jobs, :next_attempt_at))
  end

  def down do
    :noop
  end
end
