defmodule Queuetopia.LocksTest do
  use Queuetopia.DataCase

  alias Queuetopia.Locks
  alias Queuetopia.Locks.Lock

  test "release_expired_locks/2" do
    %Lock{id: id, scope: scope} = insert!(:lock)
    %Lock{} = insert!(:expired_lock, scope: scope)

    assert all_locks(scope) |> Enum.count() == 2
    assert {1, nil} = Locks.release_expired_locks(TestRepo, scope)
    assert [%Lock{id: ^id}] = all_locks(scope)
  end

  test "unlock_queue/1 removes the queue's lock" do
    %Lock{id: id, queue: queue, scope: scope} = insert!(:lock)

    assert [%Lock{id: ^id}] = all_locks(scope)

    _ = Locks.unlock_queue(TestRepo, scope, queue)

    assert TestRepo.all(Lock) == []
  end

  defp all_locks(scope) do
    Lock |> Ecto.Query.where(scope: ^scope) |> TestRepo.all()
  end
end
