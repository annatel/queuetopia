defmodule Queuetopia.SequencesTest do
  use Queuetopia.DataCase

  alias Queuetopia.Sequences

  describe "next/1" do
    test "with a valid table_name, returns the next sequence" do
      assert Sequences.next_value!(Queuetopia.TestRepo) == 1
      assert Sequences.next_value!(Queuetopia.TestRepo) == 2
    end
  end
end
