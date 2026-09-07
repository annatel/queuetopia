defmodule Queuetopia.HeldPendingQueue do
  import Ecto.Query
  import Queuetopia.Factory

  alias Queuetopia.PendingQueues
  alias Queuetopia.PendingQueues.PendingQueue
  alias Queuetopia.TestRepo

  def hold(scope, queue, test_pid) do
    spawn_link(fn ->
      test_ref = Process.monitor(test_pid)

      Ecto.Adapters.SQL.Sandbox.unboxed_run(TestRepo, fn ->
        try do
          insert!(:pending_queue, scope: scope, queue: queue)

          TestRepo.transaction(fn ->
            PendingQueues.lock_pending_queue(TestRepo, scope, queue)
            send(test_pid, :locked)

            receive do
              :release -> :ok
              {:DOWN, ^test_ref, :process, _, _} -> :ok
            after
              10_000 -> :ok
            end
          end)
        after
          TestRepo.delete_all(where(PendingQueue, scope: ^scope))
          send(test_pid, :cleaned)
        end
      end)
    end)
  end
end
