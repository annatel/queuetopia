defmodule Queuetopia.SchedulerTest do
  use Queuetopia.DataCase

  alias Queuetopia.Queue
  alias Queuetopia.Queue.{Job, Lock}
  alias Queuetopia.TestRepo
  alias Queuetopia.TestQueuetopia

  setup do
    Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 50)
    :ok
  end

  test "poll only available queues" do
    scope = TestQueuetopia.scope()

    %Job{queue: queue} = insert!(:slow_job, params: %{"duration" => 100}, scope: scope)
    lock = insert!(:lock, scope: scope, queue: queue)

    start_supervised!(TestQueuetopia)

    refute_receive {^queue, _, :started}, 50

    TestRepo.delete(lock)

    assert_receive {^queue, _, :started}, 80
    assert_receive {^queue, _, :ok}, 150
  end

  describe "concurrent jobs" do
    test "poll number_of_concurrent_jobs" do
      scope = TestQueuetopia.scope()

      %{id: job_id_1} = insert!(:slow_job, params: %{"duration" => 100}, scope: scope)
      %{id: job_id_2} = insert!(:slow_job, params: %{"duration" => 100}, scope: scope)

      on_exit(fn ->
        Application.put_env(:queuetopia, TestQueuetopia, [])
      end)

      Application.put_env(:queuetopia, TestQueuetopia,
        poll_interval: 50,
        number_of_concurrent_jobs: 2
      )

      start_supervised!(TestQueuetopia)

      assert_receive {_, ^job_id_1, :started}, 50
      assert_receive {_, ^job_id_2, :started}, 50

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "ensures concurrent jobs never pass the configured number_of_concurrent_jobs" do
      scope = TestQueuetopia.scope()

      %{id: job_id_1} = insert!(:slow_job, params: %{"duration" => 200}, scope: scope)
      %{id: job_id_2} = insert!(:slow_job, params: %{"duration" => 90}, scope: scope)

      on_exit(fn ->
        Application.put_env(:queuetopia, TestQueuetopia, [])
      end)

      Application.put_env(:queuetopia, TestQueuetopia,
        poll_interval: 50,
        number_of_concurrent_jobs: 2
      )

      start_supervised!(TestQueuetopia)

      assert_receive {_, _, :started}, 50
      assert_receive {_, _, :started}, 50
      %{jobs: jobs} = :sys.get_state(TestQueuetopia.Scheduler)
      job_ids = jobs |> Enum.map(fn {_, job} -> job.id end)
      assert job_id_1 in job_ids
      assert job_id_2 in job_ids

      %{id: job_id_3} = insert!(:slow_job, params: %{"duration" => 100}, scope: scope)

      refute_receive {_, _, :started}, 30
      %{jobs: jobs} = :sys.get_state(TestQueuetopia.Scheduler)
      job_ids = jobs |> Enum.map(fn {_, job} -> job.id end)
      assert job_id_1 in job_ids
      assert job_id_2 in job_ids

      assert_receive {_, _, :ok}, 100
      assert_receive {_, _, :started}, 100
      %{jobs: jobs} = :sys.get_state(TestQueuetopia.Scheduler)
      job_ids = jobs |> Enum.map(fn {_, job} -> job.id end)
      assert job_id_1 in job_ids
      assert job_id_3 in job_ids

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  test "poll only queues of its scope" do
    _scope = TestQueuetopia.scope()

    %Job{scope: _other_scope, queue: queue} = insert!(:slow_job, params: %{"duration" => 100})

    start_supervised!({TestQueuetopia, poll_interval: 50})

    refute_receive {^queue, _, _}, 200
  end

  test "let a long job finish while the timeout is not reached" do
    scope = TestQueuetopia.scope()

    %Job{queue: queue} =
      insert!(:slow_job,
        params: %{"duration" => 200},
        scope: scope,
        timeout: 5_000
      )

    start_supervised!({TestQueuetopia, poll_interval: 50})

    assert_receive {^queue, _, :started}, 70
    refute_receive {^queue, _, :started}, 250
    assert_receive {^queue, _, :ok}, 10

    :sys.get_state(TestQueuetopia.Scheduler)
  end

  test "locks the queue during job processing" do
    scope = TestQueuetopia.scope()

    %Job{queue: queue} =
      insert!(:slow_job,
        params: %{"duration" => 300},
        timeout: 500,
        scope: scope
      )

    start_supervised!(TestQueuetopia)

    assert_receive {^queue, _, :started}, 80
    assert %Lock{} = TestRepo.get_by(Lock, queue: queue, scope: scope)

    assert_receive {^queue, _, :ok}, 400
    refute_receive "used to wait", 500

    assert is_nil(TestRepo.get_by(Lock, queue: queue, scope: scope))

    :sys.get_state(TestQueuetopia.Scheduler)
  end

  test "keeps the lock on the queue a while (one second) after the job timeouts" do
    scope = TestQueuetopia.scope()

    %Job{queue: queue} =
      insert!(:slow_job,
        params: %{"duration" => 5_000},
        timeout: 2_000,
        scope: scope
      )

    Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 500)
    start_supervised!(TestQueuetopia)

    for pid <- Process.list(),
        do: {pid, Process.info(pid, :registered_name)} |> IO.inspect(limit: :infinity)

    assert_receive {^queue, _, :started}, 500
    assert_receive {^queue, _, :timeout}, 3_000
    refute_receive {^queue, _, :started}, 500
    assert_receive {^queue, _, :started}, 2_000
  end

  describe "isolation:" do
    test "a slow queue don't slow down the others" do
      scope = TestQueuetopia.scope()

      %{queue: fast_queue, id: fast_job_id_1} = insert!(:success_job, scope: scope)

      %{id: fast_job_id_2} = insert!(:success_job, scope: scope, queue: fast_queue)

      %{queue: slow_queue, id: slow_job_id} =
        insert!(
          :slow_job,
          scope: scope,
          params: %{"duration" => 500},
          timeout: 5_000
        )

      start_supervised!(TestQueuetopia)

      assert_receive {^slow_queue, ^slow_job_id, :started}, 200
      assert_receive {^fast_queue, ^fast_job_id_1, :ok}, 200
      refute_receive {^slow_queue, ^slow_job_id, :ok}, 200
      assert_receive {^fast_queue, ^fast_job_id_2, :ok}, 200
      refute_receive {^slow_queue, ^slow_job_id, :ok}, 200

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a failed job blocks only its own queue" do
      scope = TestQueuetopia.scope()

      %{queue: failed_queue, id: failed_job_id} = insert!(:failure_job, scope: scope)
      %{queue: success_queue, id: success_job_1} = insert!(:success_job, scope: scope)
      %{id: success_job_2} = insert!(:success_job, scope: scope, queue: success_queue)

      start_supervised!(TestQueuetopia)

      assert_receive {^success_queue, ^success_job_1, :ok}, 200
      assert_receive {^failed_queue, ^failed_job_id, :fail}, 200
      assert_receive {^success_queue, ^success_job_2, :ok}, 200
      assert_receive {^failed_queue, ^failed_job_id, :fail}, 200

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "an expired job blocks only its own queue" do
      scope = TestQueuetopia.scope()

      %{queue: expired_queue, id: slow_job_id} =
        insert!(:slow_job,
          params: %{"duration" => 500},
          scope: scope,
          timeout: 200,
          max_backoff: 0
        )

      %{queue: success_queue, id: success_job_1} = insert!(:success_job, scope: scope)
      %{id: success_job_2} = insert!(:success_job, scope: scope, queue: success_queue)

      start_supervised!(TestQueuetopia)

      assert_receive {^success_queue, ^success_job_1, :ok}, 200
      assert_receive {^expired_queue, ^slow_job_id, :started}, 200
      assert_receive {^success_queue, ^success_job_2, :ok}, 200
      assert_receive {^expired_queue, ^slow_job_id, :timeout}, 300

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a raising job blocks only its own queue" do
      scope = TestQueuetopia.scope()

      %{queue: raising_queue, id: raising_job_id} = insert!(:raising_job, scope: scope)
      %{queue: success_queue, id: success_job_1} = insert!(:success_job, scope: scope)
      %{id: success_job_2} = insert!(:success_job, scope: scope, queue: success_queue)

      start_supervised!(TestQueuetopia)

      assert_receive {^success_queue, ^success_job_1, :ok}, 200
      assert_receive {^raising_queue, ^raising_job_id, :raise}, 200
      assert_receive {^success_queue, ^success_job_2, :ok}, 200
      assert_receive {^raising_queue, ^raising_job_id, :raise}, 200
      assert_receive {^raising_queue, ^raising_job_id, :raise}, 200

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  describe "retry:" do
    test "a failed job will be retried" do
      scope = TestQueuetopia.scope()

      %{id: failing_job_id, queue: queue} = insert!(:failure_job, scope: scope, max_attempts: 1000)

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^failing_job_id, :fail}, 200
      assert_receive {^queue, ^failing_job_id, :fail}, 200
      assert_receive {^queue, ^failing_job_id, :fail}, 200
      refute_receive {^queue, :ok}, 50

      Job
      |> TestRepo.get_by(id: failing_job_id)
      |> Ecto.Changeset.change(action: "success")
      |> TestRepo.update!()

      assert_receive {^queue, ^failing_job_id, :ok}, 200

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "an expired job will be retried" do
      scope = TestQueuetopia.scope()

      %{id: slow_job_id, queue: queue} =
        insert!(:slow_job,
          params: %{"duration" => 300},
          timeout: 100,
          max_backoff: 0,
          scope: scope
        )

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^slow_job_id, :started}, 500
      assert_receive {^queue, ^slow_job_id, :timeout}, 500
      assert_receive {^queue, ^slow_job_id, :started}, 1_500
      assert_receive {^queue, ^slow_job_id, :timeout}, 500

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a raising job will be retried" do
      scope = TestQueuetopia.scope()

      %{id: raising_job_id, queue: queue} = insert!(:raising_job, scope: scope, timeout: 50)

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^raising_job_id, :raise}, 200
      assert_receive {^queue, ^raising_job_id, :raise}, 200
      assert_receive {^queue, ^raising_job_id, :raise}, 200

      Job
      |> TestRepo.get_by(id: raising_job_id)
      |> Ecto.Changeset.change(action: "success")
      |> TestRepo.update!()

      assert_receive {^queue, ^raising_job_id, :ok}, 200

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  describe "failure persistence:" do
    test "a failed job persists the failure error and set the attempt attributes" do
      scope = TestQueuetopia.scope()

      %{id: failing_job_id, queue: queue} = insert!(:failure_job, scope: scope)

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^failing_job_id, :fail}, 200
      :timer.sleep(50)

      assert %Job{
               id: ^failing_job_id,
               ended_at: nil,
               attempted_at: attempted_at,
               attempted_by: attempted_by,
               attempts: attempts,
               error: "error"
             } = Queue.get_next_pending_job(TestRepo, scope, queue)

      assert attempts > 0
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "an expired job persists the :timeout error and set the attempt attributes" do
      scope = TestQueuetopia.scope()

      %{id: slow_job_id, queue: queue} =
        insert!(:slow_job,
          params: %{"duration" => 100},
          timeout: 50,
          scope: scope
        )

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^slow_job_id, :started}, 100
      :timer.sleep(200)

      assert %Job{
               id: ^slow_job_id,
               ended_at: nil,
               attempted_at: attempted_at,
               attempted_by: attempted_by,
               attempts: attempts,
               error: "job_timeout"
             } = Queue.get_next_pending_job(TestRepo, scope, queue)

      assert attempts > 0
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "a raising job persists the :down error and set the attempt attributes" do
      scope = TestQueuetopia.scope()

      %{
        id: raising_job_id,
        scope: scope,
        queue: queue,
        attempts: 0,
        attempted_at: nil,
        attempted_by: nil,
        error: nil
      } = insert!(:raising_job, scope: scope)

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^raising_job_id, :raise}, 100
      :timer.sleep(50)

      assert %Job{
               id: ^raising_job_id,
               ended_at: nil,
               attempted_at: attempted_at,
               attempted_by: attempted_by,
               attempts: attempts,
               error: error
             } = Queue.get_next_pending_job(TestRepo, scope, queue)

      assert attempts > 0
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())
      assert error =~ "%RuntimeError{message: \"down\"}"

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  describe "repolls after job performed?:" do
    test "after a job succeeded" do
      scope = TestQueuetopia.scope()

      %{queue: queue, id: job_id_1} = insert!(:success_job, scope: scope)
      %{id: job_id_2} = insert!(:success_job, scope: scope, queue: queue)

      Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 500)

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^job_id_1, :ok}, 100
      assert_receive {^queue, ^job_id_2, :ok}, 100

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "after a job failed" do
      scope = TestQueuetopia.scope()
      Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 500)

      %{queue: queue, id: job_id_1} = insert!(:failure_job, scope: scope)

      start_supervised!(TestQueuetopia)

      assert_receive {^queue, ^job_id_1, :fail}, 1_000
      assert_receive {^queue, ^job_id_1, :fail}, 1_000

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  test "send_poll/1 sends the poll messages, only if the process inbox is empty" do
    Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 5_000)

    start_supervised!(TestQueuetopia)
    scheduler_pid = Process.whereis(TestQueuetopia.Scheduler)

    {:messages, messages} = Process.info(scheduler_pid, :messages)

    assert messages |> Enum.filter(&(elem(&1, 0) == :poll)) |> length == 0

    Queuetopia.Scheduler.send_poll(scheduler_pid)
    Queuetopia.Scheduler.send_poll(scheduler_pid)
    Queuetopia.Scheduler.send_poll(scheduler_pid)

    {:messages, messages} = Process.info(scheduler_pid, :messages)
    assert messages |> Enum.filter(&(elem(&1, 0) == :poll)) |> length == 1

    :sys.get_state(TestQueuetopia.Scheduler)
  end
end
