defmodule Queuetopia.Queue.PendingQueueTest do
  use Queuetopia.DataCase

  alias Queuetopia.Queue.PendingQueue

  test "requires scope, queue and next_runnable_at" do
    changeset = PendingQueue.changeset(%PendingQueue{}, %{})

    refute changeset.valid?

    assert %{
             scope: ["can't be blank"],
             queue: ["can't be blank"],
             next_runnable_at: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "a scope and queue pair is unique" do
    attrs = %{
      scope: "scope_1",
      queue: "queue_1",
      next_runnable_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %PendingQueue{} |> PendingQueue.changeset(attrs) |> TestRepo.insert!()

    assert {:error, changeset} =
             %PendingQueue{} |> PendingQueue.changeset(attrs) |> TestRepo.insert()

    assert %{scope: ["has already been taken"]} = errors_on(changeset)
  end
end
