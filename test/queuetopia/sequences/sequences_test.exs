defmodule Queuetopia.SequencesTest do
  use Queuetopia.DataCase

  alias Queuetopia.Sequences

  describe "next/1" do
    test "with an invalid table_name, raises a FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Sequences.next("", Queuetopia.TestRepo)
      end
    end

    test "with a valid table_name, returns the next sequence" do
      utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

      Ecto.Adapters.SQL.query!(
        Queuetopia.TestRepo,
        "INSERT INTO `queuetopia_sequences` (`sequence`, `inserted_at`, `updated_at`) VALUES ('0', ?, ?)",
        [utc_now, utc_now]
      )

      assert Sequences.next(:queuetopia_sequences, Queuetopia.TestRepo) == 1
      assert Sequences.next(:queuetopia_sequences, Queuetopia.TestRepo) == 2
    end
  end
end
