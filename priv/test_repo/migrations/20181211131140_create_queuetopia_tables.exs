defmodule Queuetopia.TestRepo.Migrations.CreateQueuetopiaTables do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.up(to_version: 1)
  end

  def down do
    Queuetopia.Migrations.down(to_version: 1)
  end
end
