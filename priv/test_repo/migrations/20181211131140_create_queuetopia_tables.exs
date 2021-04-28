defmodule Queuetopia.TestRepo.Migrations.CreateQueuetopiaTables do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.V1.up()
    Queuetopia.Migrations.V2.up()
    Queuetopia.Migrations.V3.up()
    Queuetopia.Migrations.V4.up()
  end

  def down do
    Queuetopia.Migrations.V1.down()
    Queuetopia.Migrations.V3.down()
    Queuetopia.Migrations.V4.down()
  end
end
