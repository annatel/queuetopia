defmodule Queuetopia.SchedulerTest do
  use Queuetopia.DataCase

  alias Queuetopia.Locks.Lock
  alias Queuetopia.Jobs
  alias Queuetopia.Jobs.Job
  alias Queuetopia.TestRepo
  alias Queuetopia.TestQueuetopia

  test "poll only available queues" do
    scope = TestQueuetopia.scope()

    %Job{queue: queue} = Factory.insert(:slow_job, params: %{"duration" => 100}, scope: scope)
    lock = Factory.insert(:lock, scope: scope, queue: queue)

    start_supervised!({TestQueuetopia, [poll_interval: 50]})

    refute_receive :started, 50

    TestRepo.delete(lock)

    assert_receive :started, 80
    assert_receive :ok, 150
  end

  test "poll only queues of its scope" do
    scope = TestQueuetopia.scope()

    %Job{scope: scope_2} = Factory.insert(:slow_job, params: %{"duration" => 100})

    assert scope != scope_2

    start_supervised!({TestQueuetopia, [poll_interval: 50]})

    refute_receive :started, 50
    refute_receive :started, 50
    refute_receive :started, 50
  end

  test "let a long job finish while the timeout is not reached" do
    scope = TestQueuetopia.scope()

    %Job{id: id} =
      Factory.insert(:slow_job,
        params: %{"duration" => 200},
        scope: scope,
        timeout: 5_000
      )

    start_supervised!({TestQueuetopia, [poll_interval: 50]})

    assert_receive :started, 70

    %Job{done_at: done_at} = TestRepo.get!(Job, id)
    assert is_nil(done_at)

    assert_receive :ok, 250
    refute_receive :started, 50

    %Job{done_at: done_at} = TestRepo.get!(Job, id)
    refute is_nil(done_at)

    :sys.get_state(TestQueuetopia.Scheduler)
  end

  test "locks the queue during job processing" do
    scope = TestQueuetopia.scope()

    %Job{queue: queue} =
      Factory.insert(:slow_job,
        params: %{"duration" => 300},
        timeout: 500,
        scope: scope
      )

    start_supervised!({TestQueuetopia, [poll_interval: 50]})

    assert_receive :started, 80

    lock = TestRepo.get_by(Lock, queue: queue, scope: scope)
    assert %Lock{id: id} = lock

    refute_receive :started, 50

    lock = TestRepo.get_by(Lock, queue: queue, scope: scope)
    assert %Lock{id: ^id} = lock

    assert_receive :ok, 250
    refute_receive :started, 50

    lock = TestRepo.get_by(Lock, queue: queue, scope: scope)
    assert is_nil(lock)

    :sys.get_state(TestQueuetopia.Scheduler)
  end

  test "keeps the lock on the queue a while (one second) after the job timeouts" do
    scope = TestQueuetopia.scope()

    %Job{} =
      Factory.insert(:slow_job,
        params: %{"duration" => 5_000},
        timeout: 2_000,
        scope: scope
      )

    start_supervised!({TestQueuetopia, [poll_interval: 500]})

    assert_receive :started, 500
    assert_receive :timeout, 3_000
    refute_receive :started, 500
    assert_receive :started, 2_000
  end

  describe "isolation" do
    test "a slow queue don't slow down the others" do
      scope = TestQueuetopia.scope()

      %{queue: fast_queue} = Factory.insert(:success_job)
      _ = Factory.insert(:success_job, scope: scope, queue: fast_queue)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :ok, 200

      %{id: id, queue: slow_queue} =
        Factory.insert(
          :slow_job,
          scope: scope,
          params: %{"duration" => 500},
          timeout: 5_000
        )

      assert_receive :started, 200

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, fast_queue))
      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, slow_queue)

      _ = Factory.insert(:success_job, scope: scope, queue: fast_queue)

      assert_receive :ok, 200
      assert_receive :ok, 500

      refute_receive :toto, 50

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, fast_queue))
      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, slow_queue))

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a failed job blocks only its own queue" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: failed_queue} = Factory.insert(:failure_job, scope: scope)

      %{queue: other_queue} = Factory.insert(:success_job, scope: scope)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :ok, 200
      assert_receive :fail, 200

      refute_receive :toto, 50

      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, failed_queue)
      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, other_queue))

      _ = Factory.insert(:success_job, scope: scope, queue: other_queue)

      assert_receive :ok, 200

      refute_receive :toto, 50

      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, failed_queue)
      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, other_queue))

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "an expired job blocks only its own queue" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: expired_queue} =
        Factory.insert(:slow_job,
          params: %{"duration" => 500},
          scope: scope,
          timeout: 200,
          max_backoff: 0
        )

      %{queue: other_queue} = Factory.insert(:success_job, scope: scope)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :ok, 200
      assert_receive :started, 200

      refute_receive :ok, 200
      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, other_queue))
      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, expired_queue)

      _ = Factory.insert(:success_job, scope: scope, queue: other_queue)

      assert_receive :ok, 200
      refute_receive :toto, 50

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, other_queue))
      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, expired_queue)

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a raising job blocks only its own queue" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: raising_queue} = Factory.insert(:raising_job, scope: scope)

      %{queue: success_queue} = Factory.insert(:success_job, scope: scope)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :ok, 200
      assert_receive :raise, 200

      refute_receive :toto, 50

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, success_queue))
      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, raising_queue)

      _ = Factory.insert(:success_job, scope: scope, queue: success_queue)

      assert_receive :ok, 200
      refute_receive :toto, 50

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, success_queue))
      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, raising_queue)

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  describe "retry" do
    test "a failed job will be retried" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: queue} = Factory.insert(:failure_job, scope: scope)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :fail, 200
      refute_receive :toto, 50

      assert %Job{id: ^id, error: "error"} = Jobs.get_next_pending_job(TestRepo, scope, queue)

      job = TestRepo.get_by(Job, id: id)
      job |> Ecto.Changeset.change(action: "success") |> TestRepo.update!()

      assert_receive :ok, 200
      refute_receive :toto, 50

      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, queue))

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "an expired job will be retried" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: queue} =
        Factory.insert(:slow_job,
          params: %{"duration" => 300},
          timeout: 100,
          max_backoff: 0,
          scope: scope
        )

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :started, 200
      refute_receive :ok, 300
      assert %Job{id: ^id, error: "timeout"} = Jobs.get_next_pending_job(TestRepo, scope, queue)

      job = TestRepo.get_by(Job, id: id)
      job |> Ecto.Changeset.change(action: "success") |> TestRepo.update!()

      assert_receive :ok, 1_500
      refute_receive :toto, 50
      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, queue))

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a raising job will be retried" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: queue} = Factory.insert(:raising_job, scope: scope, timeout: 50)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :raise, 200
      refute_receive :toto, 50

      assert %Job{id: ^id} = Jobs.get_next_pending_job(TestRepo, scope, queue)

      job = TestRepo.get_by(Job, id: id)
      job |> Ecto.Changeset.change(action: "success") |> TestRepo.update!()

      assert_receive :ok, 100
      refute_receive :toto, 50
      assert is_nil(Jobs.get_next_pending_job(TestRepo, scope, queue))

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  describe "failure persistence" do
    test "a failed job persists the failure error and set the attempt attributes" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: queue} = Factory.insert(:failure_job, scope: scope)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :fail, 100
      refute_receive :toto, 50

      assert %Job{
               id: ^id,
               done_at: nil,
               attempted_at: attempted_at,
               attempted_by: attempted_by,
               attempts: attempts,
               error: "error"
             } = Jobs.get_next_pending_job(TestRepo, scope, queue)

      assert attempts > 0
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "an expired job persists the :timeout error and set the attempt attributes" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: queue} =
        Factory.insert(:slow_job,
          params: %{"duration" => 100},
          timeout: 50,
          scope: scope
        )

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :started, 100
      refute_receive :toto, 200

      assert %Job{
               id: ^id,
               done_at: nil,
               attempted_at: attempted_at,
               attempted_by: attempted_by,
               attempts: attempts,
               error: "timeout"
             } = Jobs.get_next_pending_job(TestRepo, scope, queue)

      assert attempts > 0
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a raising job persists the :down error and set the attempt attributes" do
      scope = TestQueuetopia.scope()

      %{
        id: id,
        scope: scope,
        queue: queue,
        attempts: 0,
        attempted_at: nil,
        attempted_by: nil,
        error: nil
      } = Factory.insert(:raising_job, scope: scope)

      start_supervised!({TestQueuetopia, [poll_interval: 50]})

      assert_receive :raise, 100
      refute_receive :toto, 50

      assert %Job{
               id: ^id,
               done_at: nil,
               attempted_at: attempted_at,
               attempted_by: attempted_by,
               attempts: attempts,
               error: "down"
             } = Jobs.get_next_pending_job(TestRepo, scope, queue)

      assert attempts > 0
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  describe "repoll_after_job_performed?" do
    test "after a job succeeded" do
      scope = TestQueuetopia.scope()

      %{queue: queue} = Factory.insert(:success_job, scope: scope)
      _ = Factory.insert(:success_job, scope: scope, queue: queue)

      start_supervised!({TestQueuetopia, [poll_interval: 500, repoll_after_job_performed?: true]})

      assert_receive :ok, 1_000

      assert_receive :ok, 1_000
    end

    test "after a job failed" do
      scope = TestQueuetopia.scope()

      Factory.insert(:failure_job, scope: scope)

      start_supervised!({TestQueuetopia, [poll_interval: 500, repoll_after_job_performed?: true]})

      assert_receive :fail, 1_000
      assert_receive :fail, 1_000
    end
  end

  test "send_poll/1 sends the poll messages, only if the process inbox is empty" do
    start_supervised!({TestQueuetopia, [poll_interval: 5_000]})

    scheduler_pid = Process.whereis(TestQueuetopia.Scheduler)

    {:messages, messages} = Process.info(scheduler_pid, :messages)
    assert length(messages) == 0

    Queuetopia.Scheduler.send_poll(scheduler_pid)

    {:messages, messages} = Process.info(scheduler_pid, :messages)
    assert length(messages) == 1

    Queuetopia.Scheduler.send_poll(scheduler_pid)

    {:messages, messages} = Process.info(scheduler_pid, :messages)
    assert length(messages) == 1

    :sys.get_state(TestQueuetopia.Scheduler)
  end
end
