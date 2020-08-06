defmodule Queuetopia.SchedulerTest do
  use Queuetopia.DataCase

  alias Queuetopia.Locks.Lock
  alias Queuetopia.Jobs
  alias Queuetopia.Jobs.Job
  alias Queuetopia.TestRepo
  alias Queuetopia.TestQueuetopia

  setup do
    start_supervised!({TestQueuetopia, [poll_interval: 50]})
    :ok
  end

  test "poll only available queues" do
    scope = TestQueuetopia.scope()

    %Job{queue: queue} = Factory.insert(:slow_job, params: %{"duration" => 100}, scope: scope)

    lock = Factory.insert(:lock, scope: scope, queue: queue)

    refute_receive :started, 50

    TestRepo.delete(lock)

    assert_receive :started, 50

    assert_receive :ok, 150

    # :sys.get_state(TestQueuetopia.Scheduler)
  end

  test "poll only queues of its scope" do
    scope = TestQueuetopia.scope()

    %Job{scope: scope_2} = Factory.insert(:slow_job, params: %{"duration" => 100})

    assert scope != scope_2

    refute_receive :started, 50

    refute_receive :started, 50

    refute_receive :started, 50

    :sys.get_state(TestQueuetopia.Scheduler)
  end

  test "let a long job finish while the timeout is not reached" do
    scope = TestQueuetopia.scope()

    %Job{id: id} =
      Factory.insert(:slow_job,
        params: %{"duration" => 200},
        scope: scope,
        timeout: 5_000
      )

    assert_receive :started, 50

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

    assert_receive :started, 50

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

  test "keeps the lock on the queue a while after the job timeouts" do
    scope = TestQueuetopia.scope()

    %Job{id: id, queue: queue} =
      Factory.insert(:slow_job,
        params: %{"duration" => 1_500},
        timeout: 1_000,
        max_backoff: 4_000,
        scope: scope
      )

    assert_receive :started, 500
    lock = TestRepo.get_by(Lock, queue: queue, scope: scope)
    assert %Lock{id: id_1} = lock
    assert %Job{error: nil} = TestRepo.get!(Job, id)

    refute_receive :ok, 1_000
    lock = TestRepo.get_by(Lock, queue: queue, scope: scope)
    assert %Lock{id: ^id_1} = lock
    assert %Job{error: "timeout"} = TestRepo.get!(Job, id)

    refute_receive :toto, 1_000

    assert is_nil(TestRepo.get_by(Lock, queue: queue, scope: scope))

    :sys.get_state(TestQueuetopia.Scheduler)
  end

  describe "isolation" do
    test "a slow queue don't slow down the others" do
      scope = TestQueuetopia.scope()

      %{queue: fast_queue} = Factory.insert(:success_job)
      _ = Factory.insert(:success_job, scope: scope, queue: fast_queue)
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
    test "an failed job will be retried" do
      scope = TestQueuetopia.scope()

      %{id: id, queue: queue} = Factory.insert(:failure_job, scope: scope)

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
end
