defmodule Queuetopia.Migrations.V4 do
  @moduledoc false

  use Ecto.Migration

  def up do
    execute("""
    DROP FUNCTION IF EXISTS queuetopia_nextval_gapless_sequence;
    """)

    execute("""
    CREATE FUNCTION queuetopia_nextval_gapless_sequence()
    RETURNS INTEGER DETERMINISTIC
    begin
      declare next_value INTEGER;
      update queuetopia_sequences set sequence = LAST_INSERT_ID(sequence+1);
      select LAST_INSERT_ID() into next_value;
      RETURN next_value;
    end;
    """)
  end

  def down do
    execute("""
    DROP FUNCTION IF EXISTS queuetopia_nextval_gapless_sequence;
    """)
  end
end
