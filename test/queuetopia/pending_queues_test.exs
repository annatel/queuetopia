defmodule Queuetopia.PendingQueuesTest do
  use Queuetopia.DataCase

  alias Queuetopia.PendingQueues
  alias Queuetopia.Jobs
  alias Queuetopia.Jobs.Job
  alias Queuetopia.PendingQueues.PendingQueue

  describe "list_available_pending_queues/1" do
    test "returns the scoped queues whose next_performable_at is reached" do
      %{queue: queue, scope: scope} = insert_pending_job!(:job)

      assert [^queue] = PendingQueues.list_available_pending_queues(TestRepo, scope)
    end

    test "don't list queues whose next_performable_at is not reached yet" do
      %{scope: scope} = insert_pending_job!(:job, scheduled_at: utc_now() |> add(3600))

      assert [] = PendingQueues.list_available_pending_queues(TestRepo, scope)
    end

    test "don't list queues without pending row (done or exhausted jobs)" do
      %{scope: scope_1} = insert!(:done_job)

      %{scope: scope_2} =
        insert!(:job, scheduled_at: utc_now() |> add(-3600), attempts: 5, max_attempts: 5)

      assert [] = PendingQueues.list_available_pending_queues(TestRepo, scope_1)
      assert [] = PendingQueues.list_available_pending_queues(TestRepo, scope_2)
    end

    test "when limit is given, returns only the specified number of rows from the result set" do
      %{scope: scope} = insert_pending_job!(:job)
      insert_pending_job!(:job, scope: scope)

      assert [_] = PendingQueues.list_available_pending_queues(TestRepo, scope, limit: 1)
    end

    test "when a queue is locked" do
      %{queue: queue_1, scope: scope_1} = insert_pending_job!(:job)
      _ = insert!(:lock, queue: queue_1, scope: scope_1)

      assert [] = PendingQueues.list_available_pending_queues(TestRepo, scope_1)
    end

    test "there is no collision between two queues with the same name but in different scope" do
      %{queue: queue, scope: scope_1} = insert_pending_job!(:job)
      %{scope: scope_2} = insert_pending_job!(:job, queue: queue)

      _ = insert!(:lock, queue: queue, scope: scope_1)

      assert [] = PendingQueues.list_available_pending_queues(TestRepo, scope_1)
      assert [^queue] = PendingQueues.list_available_pending_queues(TestRepo, scope_2)
    end

    test "a new job on a queue in backoff makes it listed until the queue is refreshed" do
      %{queue: queue, scope: scope} =
        job =
        insert_pending_job!(:failure_job,
          scope: Queuetopia.TestQueuetopia.scope(),
          max_backoff: 3_600_000
        )

      Jobs.persist_result!(TestRepo, job, {:error, "error"})

      assert [] = PendingQueues.list_available_pending_queues(TestRepo, scope)

      {:ok, _} =
        Jobs.create_job(
          job_attrs(params_for(:job, scope: scope, queue: queue)),
          TestRepo
        )

      assert [^queue] = PendingQueues.list_available_pending_queues(TestRepo, scope)

      PendingQueues.refresh_pending_queue!(TestRepo, scope, queue)

      assert [] = PendingQueues.list_available_pending_queues(TestRepo, scope)
    end
  end

  describe "pending queues maintenance" do
    test "create_job registers the queue as pending, performable at the job's scheduled_at" do
      params = params_for(:job)
      attrs = job_attrs(params)

      assert {:ok, %Job{}} = Jobs.create_job(attrs, TestRepo)

      assert %PendingQueue{next_performable_at: next_performable_at} =
               get_pending_queue(params.scope, params.queue)

      assert DateTime.compare(
               next_performable_at,
               DateTime.truncate(params.scheduled_at, :second)
             ) ==
               :eq
    end

    test "create_job keeps the earliest next_performable_at of the queue" do
      utc_now = utc_now() |> DateTime.truncate(:second)
      params = params_for(:job, scheduled_at: utc_now |> DateTime.add(3600))

      {:ok, _} = Jobs.create_job(job_attrs(params), TestRepo)

      {:ok, _} =
        Jobs.create_job(
          job_attrs(
            params_for(:job, queue: params.queue, scope: params.scope, scheduled_at: utc_now)
          ),
          TestRepo
        )

      {:ok, _} =
        Jobs.create_job(
          job_attrs(
            params_for(:job,
              queue: params.queue,
              scope: params.scope,
              scheduled_at: utc_now |> DateTime.add(7200)
            )
          ),
          TestRepo
        )

      assert %PendingQueue{next_performable_at: next_performable_at} =
               get_pending_queue(params.scope, params.queue)

      assert DateTime.compare(next_performable_at, utc_now) == :eq
    end

    test "a succeeded job moves next_performable_at to the next job of the queue" do
      utc_now = utc_now() |> DateTime.truncate(:second)
      later = utc_now |> DateTime.add(3600)

      job =
        insert_pending_job!(:success_job,
          scope: Queuetopia.TestQueuetopia.scope(),
          scheduled_at: utc_now
        )

      insert!(:job, scope: job.scope, queue: job.queue, scheduled_at: later)

      Jobs.persist_result!(TestRepo, job, :ok)

      assert %PendingQueue{next_performable_at: next_performable_at} =
               get_pending_queue(job.scope, job.queue)

      assert DateTime.compare(next_performable_at, later) == :eq
    end

    test "a succeeded last job removes the pending queue" do
      job = insert_pending_job!(:success_job, scope: Queuetopia.TestQueuetopia.scope())

      Jobs.persist_result!(TestRepo, job, :ok)

      assert is_nil(get_pending_queue(job.scope, job.queue))
    end

    test "a failed job pushes next_performable_at to its next attempt" do
      job =
        insert_pending_job!(:failure_job,
          scope: Queuetopia.TestQueuetopia.scope(),
          max_backoff: 60_000
        )

      Jobs.persist_result!(TestRepo, job, {:error, "error"})

      %Job{next_attempt_at: next_attempt_at} = TestRepo.reload(job)

      assert %PendingQueue{next_performable_at: next_performable_at} =
               get_pending_queue(job.scope, job.queue)

      assert DateTime.compare(next_performable_at, next_attempt_at) == :eq
    end
  end

  defp job_attrs(params) do
    Map.take(params, [
      :scope,
      :queue,
      :sequence,
      :action,
      :params,
      :scheduled_at,
      :timeout,
      :max_backoff,
      :max_attempts
    ])
  end

  describe "lock_pending_queue/3" do
    test "fails immediately instead of waiting behind a held row" do
      scope = "scope_#{System.unique_integer([:positive])}"
      queue = "queue_#{System.unique_integer([:positive])}"
      test_pid = self()

      holder =
        spawn_link(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(TestRepo, fn ->
            build(:pending_queue, scope: scope, queue: queue) |> TestRepo.insert!()

            TestRepo.transaction(fn ->
              PendingQueues.lock_pending_queue(TestRepo, scope, queue)
              send(test_pid, :locked)

              receive do
                :release -> :ok
              end
            end)

            TestRepo.delete_all(Ecto.Query.where(PendingQueue, scope: ^scope))
            send(test_pid, :cleaned)
          end)
        end)

      assert_receive :locked, 1_000

      spawn_link(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(TestRepo, fn ->
          {elapsed_us, _} =
            :timer.tc(fn ->
              assert_raise MyXQL.Error, ~r/NOWAIT/, fn ->
                TestRepo.transaction(fn ->
                  PendingQueues.lock_pending_queue(TestRepo, scope, queue)
                end)
              end
            end)

          send(test_pid, {:contended, elapsed_us})
        end)
      end)

      assert_receive {:contended, elapsed_us}, 5_000
      assert elapsed_us < 1_000_000

      send(holder, :release)
      assert_receive :cleaned, 1_000
    end
  end

  defp get_pending_queue(scope, queue) do
    PendingQueue
    |> Ecto.Query.where(scope: ^scope, queue: ^queue)
    |> TestRepo.one()
  end
end
