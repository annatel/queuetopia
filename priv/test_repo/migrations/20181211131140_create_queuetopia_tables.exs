defmodule Queuetopia.TestRepo.Migrations.CreateQueuetopiaTables do
  use Ecto.Migration

  def up do
    Queuetopia.Migrations.V1.up()
  end

  def down do
    Queuetopia.Migrations.V1.down()
  end
end
