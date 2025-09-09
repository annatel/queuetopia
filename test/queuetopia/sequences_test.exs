defmodule Queuetopia.SequencesTest do
  use Queuetopia.DataCase

  alias Queuetopia.Sequences

  describe "next/1" do
    test "with an invalid table_name, raises a FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Sequences.next_value!("", Queuetopia.TestRepo)
      end
    end

    test "with a valid table_name, returns the next sequence" do
      assert Sequences.next_value!(:queuetopia_sequences, Queuetopia.TestRepo) == 1
      assert Sequences.next_value!(:queuetopia_sequences, Queuetopia.TestRepo) == 2
    end
  end
end
