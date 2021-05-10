defmodule Queuetopia.TestRepo.Migrations.CreateQueuetopiaTables do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.up(from_version: 0, to_version: 1)
  end

  def down do
    Queuetopia.Migrations.down(from_version: 1, to_version: 0)
  end
end
