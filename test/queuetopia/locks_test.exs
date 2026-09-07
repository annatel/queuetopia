defmodule Queuetopia.LocksTest do
  use Queuetopia.DataCase

  alias Queuetopia.Locks
  alias Queuetopia.Locks.Lock

  test "lock_queue/4 holds the lock a whole extra second past the job timeout" do
    before = DateTime.utc_now()

    {:ok, %Lock{locked_until: locked_until}} = Locks.lock_queue(TestRepo, "scope", "queue", 0)

    margin = DateTime.diff(locked_until, before, :millisecond)
    assert margin >= 1_000 and margin < 2_000
    assert locked_until.microsecond == {0, 0}
  end

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
