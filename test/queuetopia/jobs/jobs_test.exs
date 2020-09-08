defmodule Queuetopia.JobsTest do
  use Queuetopia.DataCase

  alias Queuetopia.Jobs
  alias Queuetopia.Jobs.Job
  alias Queuetopia.Locks.Lock

  describe "list_available_pending_queues/1" do
    test "returns available scoped queues with pending jobs" do
      %{queue: _queue_1, scope: scope_1} = Factory.insert(:done_job)

      %{queue: queue_2, scope: scope_2} = Factory.insert(:job)
      _ = Factory.insert(:done_job, queue: queue_2, scope: scope_2)

      assert [] = Jobs.list_available_pending_queues(TestRepo, scope_1)
      assert [^queue_2] = Jobs.list_available_pending_queues(TestRepo, scope_2)
    end

    test "when a queue is locked" do
      %{queue: queue_1, scope: scope_1} = Factory.insert(:job)
      _ = Factory.insert(:lock, queue: queue_1, scope: scope_1)

      assert [] = Jobs.list_available_pending_queues(TestRepo, scope_1)
    end

    test "collision between two queues with the same name but in different scope" do
      %{queue: queue, scope: scope_1} = Factory.insert(:job)
      %{scope: scope_2} = Factory.insert(:job, queue: queue)

      _ = Factory.insert(:lock, queue: queue, scope: scope_1)

      assert [] = Jobs.list_available_pending_queues(TestRepo, scope_1)
      assert [queue] = Jobs.list_available_pending_queues(TestRepo, scope_2)
    end
  end

  describe "get_next_pending_job/2" do
    test "returns the next pending job for a given scoped queue " do
      %{queue: queue_1, scope: scope_1} = Factory.insert(:done_job)
      %{id: id_1} = Factory.insert(:job, queue: queue_1, scope: scope_1)

      %{id: id_2, queue: queue_2} = Factory.insert(:job, scope: scope_1)

      %{id: id_3, queue: queue_3, scope: scope_2} = Factory.insert(:job)

      assert %Job{id: ^id_1} = Jobs.get_next_pending_job(TestRepo, scope_1, queue_1)
      assert %Job{id: ^id_2} = Jobs.get_next_pending_job(TestRepo, scope_1, queue_2)
      assert %Job{id: ^id_3} = Jobs.get_next_pending_job(TestRepo, scope_2, queue_3)
    end

    test "when the queue is empty, returns nil" do
      %{queue: queue, scope: scope} = Factory.insert(:done_job)

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, queue))
    end

    test "when the queue does not exist, returns nil" do
      %{queue: queue, scope: scope} = Factory.params_for(:job)

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, queue))
    end

    test "when the next pending job is scheduled for later" do
      %Job{queue: queue, scope: scope} =
        Factory.insert(:job, scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second))

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, queue))
    end
  end

  describe "fetch_job/2" do
    test "locks the queue for the job's timeout and returns the job" do
      %Job{id: id, queue: queue, scope: scope} = job = Factory.insert(:job, timeout: 1_000)

      assert {:ok, %Job{id: ^id}} = Jobs.fetch_job(TestRepo, job)

      assert %Lock{locked_until: locked_until, locked_at: locked_at} =
               TestRepo.get_by(Lock, scope: scope, queue: queue)

      assert locked_until = DateTime.add(locked_at, 1_000, :second)
    end

    test "when the queue is already locked" do
      %Job{queue: queue, scope: scope} = job = Factory.insert(:job)
      %Lock{id: id} = Factory.insert(:lock, queue: queue, scope: scope)

      assert {:error, :locked} = Jobs.fetch_job(TestRepo, job)
      assert %Lock{id: ^id} = TestRepo.get_by(Lock, scope: scope, queue: queue)
    end

    test "when the job is done" do
      %Job{queue: queue, scope: scope} = job = Factory.insert(:done_job)

      assert {:error, "already done"} = Jobs.fetch_job(TestRepo, job)
      assert is_nil(TestRepo.get_by(Lock, scope: scope, queue: queue))
    end

    test "when the job is scheduled for later" do
      %Job{queue: queue, scope: scope} =
        job =
        Factory.insert(:job, scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second))

      assert {:error, "scheduled for later"} = Jobs.fetch_job(TestRepo, job)
      assert is_nil(TestRepo.get_by(Lock, scope: scope, queue: queue))
    end
  end

  describe "create_job/5" do
    test "with valid params, returns the created job" do
      params = Factory.params_for(:job)

      opts = [
        timeout: params.timeout,
        max_backoff: params.max_backoff,
        max_attempts: params.max_attempts
      ]

      assert {:ok, %Job{} = job} =
               Jobs.create_job(
                 TestRepo,
                 params.performer,
                 params.scope,
                 params.queue,
                 params.action,
                 params.params,
                 opts
               )

      assert job.sequence == 1
      assert job.scope == params.scope
      assert job.queue == params.queue
      assert job.performer == to_string(params.performer)
      assert job.action == params.action
      assert job.params == params.params
      assert not is_nil(job.scheduled_at)
      assert job.timeout == params.timeout
      assert job.max_backoff == params.max_backoff
      assert job.max_attempts == params.max_attempts
    end

    test "when options are not set, creates the job with the default options" do
      params = Factory.params_for(:job)

      assert {:ok, %Job{} = job} =
               Jobs.create_job(
                 TestRepo,
                 params.performer,
                 params.scope,
                 params.queue,
                 params.action,
                 params.params
               )

      assert job.timeout == Job.default_timeout()
      assert job.max_backoff == Job.default_max_backoff()
      assert job.max_attempts == Job.default_max_attempts()
    end

    test "with invalid params, returns a changeset error" do
      assert {:error, changeset} = Jobs.create_job(TestRepo, nil, nil, nil, nil, nil)
      refute changeset.valid?
    end
  end

  test "perform/1" do
    job = Factory.insert(:success_job)
    assert Jobs.perform(job) == :ok
  end

  describe "persist_result/4" do
    test "when a job succeeded, persists the job as succeeded" do
      %Job{id: id} = job = Factory.insert(:success_job)

      _ = Jobs.persist_result(TestRepo, job, :ok)

      %Job{
        done_at: done_at,
        attempted_at: attempted_at,
        attempted_by: attempted_by,
        attempts: attempts
      } = TestRepo.get_by(Job, id: id)

      refute is_nil(done_at)
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())
      assert attempts == 1
      assert done_at == attempted_at
    end

    test "when a job succeeded with a result, persists the job as succeeded" do
      %Job{id: id} = job = Factory.insert(:success_job)

      _ = Jobs.persist_result(TestRepo, job, {:ok, :done})

      %Job{
        done_at: done_at,
        attempted_at: attempted_at,
        attempted_by: attempted_by,
        attempts: attempts
      } = TestRepo.get_by(Job, id: id)

      refute is_nil(done_at)
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())
      assert attempts == 1
      assert done_at == attempted_at
    end

    test "when a job failed, persists the job as failed" do
      %{id: id} = job = Factory.insert(:failure_job)

      _ = Jobs.persist_result(TestRepo, job, {:error, "error"})

      %Job{
        done_at: nil,
        attempted_at: attempted_at,
        attempted_by: attempted_by,
        attempts: attempts
      } = TestRepo.get_by(Job, id: id)

      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())
      assert attempts == 1
    end

    test "backoff is exponential for retry" do
      %{id: id} = Factory.insert(:failure_job, max_backoff: 10 * 60 * 1_000)

      [2_000, 3_000, 5_000, 9_000, 17_000]
      |> Enum.each(fn backoff ->
        job = TestRepo.get_by(Job, id: id)

        Jobs.persist_result(TestRepo, job, {:error, "error"})

        %Job{
          done_at: nil,
          attempted_at: attempted_at,
          scheduled_at: scheduled_at
        } = TestRepo.get_by(Job, id: id)

        assert scheduled_at == DateTime.add(attempted_at, backoff, :millisecond)
      end)
    end

    test "maximum backoff" do
      max_backoff = 2_000

      %{id: id} = job = Factory.insert(:failure_job, max_backoff: max_backoff)

      _ = Jobs.persist_result(TestRepo, job, {:error, "error"})

      %Job{
        done_at: nil,
        attempted_at: attempted_at,
        scheduled_at: scheduled_at
      } = TestRepo.get_by(Job, id: id)

      assert scheduled_at == DateTime.add(attempted_at, max_backoff, :millisecond)

      _ = Jobs.persist_result(TestRepo, job, {:error, "error"})

      %Job{
        done_at: nil,
        attempted_at: attempted_at,
        scheduled_at: scheduled_at
      } = TestRepo.get_by(Job, id: id)

      assert scheduled_at == DateTime.add(attempted_at, max_backoff, :millisecond)
    end
  end

  describe "processable_now?/1" do
    test "when the job is processable now" do
      job = Factory.insert(:job)
      assert Jobs.processable_now?(job)
    end

    test "when the job is done" do
      job = Factory.insert(:done_job)
      refute Jobs.processable_now?(job)
    end

    test "when the job is scheduled for later" do
      job = Factory.insert(:job, scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second))
      refute Jobs.processable_now?(job)
    end
  end

  describe "done?/1" do
    test "when the job is not done" do
      job = Factory.insert(:job)
      refute Jobs.done?(job)
    end

    test "when the job is done" do
      job = Factory.insert(:done_job)
      assert Jobs.done?(job)
    end
  end

  describe "scheduled_for_now?/1" do
    test "when the job is scheduled for now" do
      job = Factory.insert(:job)
      assert Jobs.scheduled_for_now?(job)
    end

    test "when the job is done" do
      job = Factory.insert(:job, scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second))
      refute Jobs.scheduled_for_now?(job)
    end
  end
end
