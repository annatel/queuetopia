defmodule Queuetopia.TestRepo.Migrations.AlterTableQueuetopiaTableAddNextAttemptAt do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.up(from_version: 2, to_version: 3)
  end

  def down do
    Queuetopia.Migrations.down(to_version: 2)
  end
end
