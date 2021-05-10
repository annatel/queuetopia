defmodule Queuetopia.Migrations.V2 do
  @moduledoc false

  use Ecto.Migration
  alias Queuetopia.Migrations.Helper

  def up do
    Helper.create_index_if_not_exists(:queuetopia_jobs, [:scheduled_at, :sequence])
  end

  def down do
    :noop
  end
end
