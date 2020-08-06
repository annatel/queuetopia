defmodule Queuetopia.LocksTest do
  use Queuetopia.DataCase

  alias Queuetopia.Locks
  alias Queuetopia.Locks.Lock

  test "release_expired_locks/2" do
    %Lock{id: id, scope: scope} = Factory.insert(:lock)
    %Lock{} = Factory.insert(:expired_lock, scope: scope)

    assert all_locks(scope) |> Enum.count() == 2
    assert {1, nil} = Locks.release_expired_locks(TestRepo, scope)
    assert [%Lock{id: ^id}] = all_locks(scope)
  end

  describe "lock_queue/2" do
    test "when the queue is available, locks it" do
      %{queue: queue, scope: scope} = Factory.params_for(:lock)

      assert {:ok, %Lock{queue: ^queue, scope: ^scope}} =
               Locks.lock_queue(TestRepo, scope, queue, 1_000)
    end

    test "when the queue is locked, returns an error" do
      %Lock{queue: queue, scope: scope} = Factory.insert(:lock)

      assert {:error, :locked} = Locks.lock_queue(TestRepo, scope, queue, 1_000)
    end

    test "althought the lock is expired, if it exists, returns an error" do
      %Lock{queue: queue, scope: scope} = Factory.insert(:expired_lock)

      assert {:error, :locked} = Locks.lock_queue(TestRepo, scope, queue, 1_000)
    end
  end

  test "unlock_queue/1 removes the queue's lock" do
    %Lock{id: id, queue: queue, scope: scope} = Factory.insert(:lock)

    assert [%Lock{id: ^id}] = all_locks(scope)

    _ = Locks.unlock_queue(TestRepo, scope, queue)

    assert TestRepo.all(Lock) == []
  end

  defp all_locks(scope) do
    Lock |> Ecto.Query.where(scope: ^scope) |> TestRepo.all()
  end
end
