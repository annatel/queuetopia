defmodule Queuetopia.Migrations.V6 do
  @moduledoc false

  use Ecto.Migration

  def up do
    drop(index(:queuetopia_jobs, [:sequence]))

    create(unique_index(:queuetopia_jobs, [:sequence]))
  end

  def down do
    :noop
  end
end
