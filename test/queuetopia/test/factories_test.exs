defmodule Queuetopia.FactoriesTest do
  use Queuetopia.DataCase

  alias Queuetopia.Factories
  alias Queuetopia.PendingQueues
  alias Queuetopia.PendingQueues.PendingQueue

  test "build(:pending_queue) seeds a row making the queue visible to the poll" do
    job = Factories.build(:job, %{})

    pending_queue =
      Factories.build(:pending_queue, %{
        scope: job.scope,
        queue: job.queue,
        next_performable_at: DateTime.truncate(job.scheduled_at, :second)
      })

    assert %PendingQueue{} = TestRepo.insert!(pending_queue)
    assert [job.queue] == PendingQueues.list_available_pending_queues(TestRepo, job.scope)
  end
end
