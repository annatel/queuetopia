defmodule Queuetopia.TestRepo.Migrations.AlterTableQueuetopiaTableAddNextAttemptAt do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.up(from_version: 1, to_version: 3)
  end

  def down do
    Queuetopia.Migrations.down(from_version: 3, to_version: 1)
  end
end
