defmodule Queuetopia.TestRepo.Migrations.AlterTableQueuetopiaTableAddNextAttemptAt do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.V2.up()
    Queuetopia.Migrations.V3.up()
  end

  def down do
    Queuetopia.Migrations.V3.down()
  end


end
