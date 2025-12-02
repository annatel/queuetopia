defmodule Queuetopia.JobCleanerTest do
  use Queuetopia.DataCase, async: false

  alias Queuetopia.Queue.Job
  alias Queuetopia.TestRepo
  alias Queuetopia.TestQueuetopia

  defp datetime_days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days, :day)
    |> DateTime.truncate(:second)
  end

  test "removes completed jobs older than 7 days retention period during periodic cleanup" do
    start_supervised!(
      {TestQueuetopia, cleanup_interval: {100, :millisecond}, job_cleaner_initial_delay: 0}
    )

    :timer.sleep(100)

    eight_days_old_job =
      insert!(:job,
        scope: TestQueuetopia.scope(),
        done_at: datetime_days_ago(8)
      )

    six_days_old_job =
      insert!(:job,
        scope: TestQueuetopia.scope(),
        done_at: datetime_days_ago(6)
      )

    :timer.sleep(60)

    assert is_nil(TestRepo.get(Job, eight_days_old_job.id))
    assert TestRepo.get(Job, six_days_old_job.id)
  end

  test "only removes jobs from its own scope" do
    our_queue_scope = TestQueuetopia.scope()
    other_queue_scope = "other_queue"

    our_eight_days_old_job =
      insert!(:job,
        scope: our_queue_scope,
        done_at: datetime_days_ago(8)
      )

    other_eight_days_old_job =
      insert!(:job,
        scope: other_queue_scope,
        done_at: datetime_days_ago(8)
      )

    start_supervised!(
      {TestQueuetopia, cleanup_interval: {100, :millisecond}, job_cleaner_initial_delay: 0}
    )

    :timer.sleep(100)

    assert is_nil(TestRepo.get(Job, our_eight_days_old_job.id))
    assert TestRepo.get(Job, other_eight_days_old_job.id)
  end

  test "starts cleanup immediately when JobCleaner starts" do
    scope = TestQueuetopia.scope()

    eight_days_old_completed_job =
      insert!(:job,
        scope: scope,
        done_at: datetime_days_ago(8)
      )

    assert TestRepo.get(Job, eight_days_old_completed_job.id)

    start_supervised!(
      {TestQueuetopia, cleanup_interval: {100, :millisecond}, job_cleaner_initial_delay: 0}
    )

    :timer.sleep(50)

    assert is_nil(TestRepo.get(Job, eight_days_old_completed_job.id))
  end

  test "cleanup is disabled by default" do
    old_job = insert!(:job, scope: "default_scope", done_at: datetime_days_ago(30))
    recent_job = insert!(:job, scope: "default_scope", done_at: datetime_days_ago(1))

    Application.put_env(:queuetopia, TestQueuetopia, [])
    start_supervised!(TestQueuetopia)

    :timer.sleep(100)

    assert TestRepo.get(Job, old_job.id)
    assert TestRepo.get(Job, recent_job.id)
  end

  test "respects job_cleaner_initial_delay before first cleanup" do
    scope = TestQueuetopia.scope()

    eight_days_old_job =
      insert!(:job,
        scope: scope,
        done_at: datetime_days_ago(8)
      )

    start_supervised!(
      {TestQueuetopia, cleanup_interval: {100, :millisecond}, job_cleaner_initial_delay: 20}
    )

    :timer.sleep(10)
    assert TestRepo.get(Job, eight_days_old_job.id), "Job should still exist before initial delay"

    :timer.sleep(15)

    assert is_nil(TestRepo.get(Job, eight_days_old_job.id)),
           "Job should be deleted after initial delay"
  end
end
