defmodule Queuetopia.JobCleanerTest do
  use Queuetopia.DataCase

  alias Queuetopia.Queue.Job
  alias Queuetopia.TestRepo
  alias Queuetopia.TestQueuetopia

  defp datetime_ago(seconds) do
    DateTime.utc_now()
    |> DateTime.add(-seconds, :second)
    |> DateTime.truncate(:second)
  end

  defp days_in_seconds(days), do: days * 24 * 60 * 60

  setup do
    Application.put_env(:queuetopia, TestQueuetopia, cleanup_interval: {50, :millisecond})

    on_exit(fn ->
      Application.put_env(:queuetopia, TestQueuetopia, [])
    end)

    :ok
  end

  test "removes completed jobs older than 7 days retention period" do
    scope = TestQueuetopia.scope()

    eight_days_old_completed_job =
      insert!(:job,
        scope: scope,
        done_at: datetime_ago(days_in_seconds(8))
      )

    six_days_old_completed_job =
      insert!(:job,
        scope: scope,
        done_at: datetime_ago(days_in_seconds(6))
      )

    pending_job_without_done_at =
      insert!(:job,
        scope: scope,
        done_at: nil
      )

    start_supervised!(TestQueuetopia)
    :timer.sleep(100)

    assert is_nil(TestRepo.get(Job, eight_days_old_completed_job.id))
    assert TestRepo.get(Job, six_days_old_completed_job.id)
    assert TestRepo.get(Job, pending_job_without_done_at.id)
  end

  test "only removes jobs from its own scope" do
    our_queue_scope = TestQueuetopia.scope()
    other_queue_scope = "other_queue"

    our_eight_days_old_job =
      insert!(:job,
        scope: our_queue_scope,
        done_at: datetime_ago(days_in_seconds(8))
      )

    other_eight_days_old_job =
      insert!(:job,
        scope: other_queue_scope,
        done_at: datetime_ago(days_in_seconds(8))
      )

    start_supervised!(TestQueuetopia)
    :timer.sleep(100)

    assert is_nil(TestRepo.get(Job, our_eight_days_old_job.id))
    assert TestRepo.get(Job, other_eight_days_old_job.id)
  end
end
