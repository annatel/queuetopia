defmodule Queuetopia.JobsTest do
  use Queuetopia.DataCase

  alias Queuetopia.Jobs
  alias Queuetopia.Jobs.Job
  alias Queuetopia.Locks.Lock

  describe "acquire_next_performable_job/3" do
    test "acquires the next performable job and locks the queue" do
      %{id: id, queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now())
      insert!(:job, queue: queue, scope: scope, scheduled_at: utc_now() |> add(60))

      assert {:ok, %Job{id: ^id}} = Jobs.acquire_next_performable_job(TestRepo, scope, queue)

      assert %Lock{locked_until: locked_until, locked_at: locked_at} =
               TestRepo.get_by(Lock, scope: scope, queue: queue)

      assert locked_until ==
               locked_at |> DateTime.add(6_000, :millisecond) |> DateTime.truncate(:second)
    end

    test "when the queue has an expired lock, still returns an error" do
      %{queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now())
      insert!(:expired_lock, scope: scope, queue: queue)

      assert {:error, :locked} = Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when the queue is already locked, returns an error and acquires nothing" do
      %{queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now())
      insert!(:lock, scope: scope, queue: queue)

      assert {:error, :locked} = Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when the head job is not performable yet, returns an error without locking the queue" do
      %{queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now() |> add(3600))

      assert {:error, :no_performable_job} =
               Jobs.acquire_next_performable_job(TestRepo, scope, queue)

      assert is_nil(TestRepo.get_by(Lock, scope: scope, queue: queue))
    end

    test "when the queue has no pending job, returns an error without locking the queue" do
      %{queue: queue, scope: scope} = insert!(:done_job)

      assert {:error, :no_performable_job} =
               Jobs.acquire_next_performable_job(TestRepo, scope, queue)

      assert is_nil(TestRepo.get_by(Lock, scope: scope, queue: queue))
    end
  end

  describe "acquire_next_performable_job/3 — next job selection" do
    test "returns the next pending job for a given scoped queue" do
      %{queue: queue_1, scope: scope_1} = insert!(:done_job)
      %{id: id_1} = insert!(:job, queue: queue_1, scope: scope_1)

      %{id: id_2, queue: queue_2} = insert!(:job, scope: scope_1)

      %{id: id_3, queue: queue_3, scope: scope_2} = insert!(:job)

      assert {:ok, %Job{id: ^id_1}} =
               Jobs.acquire_next_performable_job(TestRepo, scope_1, queue_1)

      assert {:ok, %Job{id: ^id_2}} =
               Jobs.acquire_next_performable_job(TestRepo, scope_1, queue_2)

      assert {:ok, %Job{id: ^id_3}} =
               Jobs.acquire_next_performable_job(TestRepo, scope_2, queue_3)
    end

    test "preseance by scheduled_at" do
      utc_now = utc_now()

      %{scope: scope, queue: queue} =
        insert!(:job, scheduled_at: utc_now |> DateTime.add(15, :second))

      %{id: id} =
        insert!(:job,
          scope: scope,
          queue: queue,
          scheduled_at: utc_now
        )

      assert {:ok, %Job{id: ^id}} = Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "for multiple jobs with the same scheduled_at, preseance by sequence" do
      utc_now = utc_now()

      %{id: id_1, scope: scope, queue: queue} = insert!(:job, scheduled_at: utc_now, sequence: 1)

      insert!(:job, scope: scope, queue: queue, scheduled_at: utc_now, sequence: 2)

      assert {:ok, %Job{id: ^id_1}} = Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when the queue is empty" do
      %{queue: queue, scope: scope} = insert!(:done_job)

      assert {:error, :no_performable_job} =
               Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when the queue does not exist" do
      %{queue: queue, scope: scope} = params_for(:job)

      assert {:error, :no_performable_job} =
               Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when the next pending job is scheduled for later" do
      %Job{queue: queue, scope: scope} =
        insert!(:job, scheduled_at: utc_now() |> add(3600, :second))

      assert {:error, :no_performable_job} =
               Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when the next pending job next attempt is scheduled for now" do
      %Job{queue: queue, scope: scope, id: id} = insert!(:job, next_attempt_at: utc_now())

      assert {:ok, %Job{id: ^id}} = Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when the next pending job next attempt is scheduled for later" do
      %Job{queue: queue, scope: scope} =
        insert!(:job, next_attempt_at: utc_now() |> add(3600, :second))

      assert {:error, :no_performable_job} =
               Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end

    test "when max job attempts is reached" do
      %Job{queue: queue, scope: scope} =
        insert!(:job, next_attempt_at: utc_now(), attempts: 20, max_attempts: 20)

      assert {:error, :no_performable_job} =
               Jobs.acquire_next_performable_job(TestRepo, scope, queue)
    end
  end

  test "perform/1" do
    job = insert!(:success_job, scope: Queuetopia.TestQueuetopia.scope())
    assert Jobs.perform(job) == :ok
  end

  describe "persist_result!/4" do
    test "commits the result and survives when the pending row is held by another transaction" do
      scope = "scope_#{System.unique_integer([:positive])}"
      queue = "queue_#{System.unique_integer([:positive])}"
      test_pid = self()

      holder =
        spawn_link(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(TestRepo, fn ->
            job = insert_pending_job!(:success_job, scope: scope, queue: queue)
            send(test_pid, {:seeded, job})

            TestRepo.transaction(fn ->
              Queuetopia.PendingQueues.lock_pending_queue(TestRepo, scope, queue)
              send(test_pid, :locked)

              receive do
                :release -> :ok
              end
            end)

            TestRepo.delete_all(Ecto.Query.where(Job, scope: ^scope))

            TestRepo.delete_all(
              Ecto.Query.where(Queuetopia.PendingQueues.PendingQueue, scope: ^scope)
            )

            TestRepo.query!("UPDATE queuetopia_sequences SET sequence = sequence - 1")
            send(test_pid, :cleaned)
          end)
        end)

      assert_receive {:seeded, job}, 1_000
      assert_receive :locked, 1_000

      spawn_link(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(TestRepo, fn ->
          log =
            ExUnit.CaptureLog.capture_log(fn ->
              %Job{} = Jobs.persist_result!(TestRepo, job, :ok)
            end)

          send(test_pid, {:persisted, TestRepo.get(Job, job.id), log})
        end)
      end)

      assert_receive {:persisted, %Job{} = done_job, log}, 5_000
      refute is_nil(done_job.done_at)
      assert is_nil(done_job.error)
      assert log =~ "Refreshing the pending queue"

      send(holder, :release)
      assert_receive :cleaned, 1_000
    end

    test "when a job succeeded, persists the job as succeeded" do
      job = insert!(:success_job)

      _ = Jobs.persist_result!(TestRepo, job, :ok)

      %Job{
        done_at: done_at,
        attempted_at: attempted_at,
        attempted_by: attempted_by,
        attempts: attempts
      } = TestRepo.reload(job)

      refute is_nil(done_at)
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())
      assert attempts == 1
      assert done_at == attempted_at
    end

    test "when a job succeeded with a result, persists the job as succeeded" do
      job = insert!(:success_job)

      _ = Jobs.persist_result!(TestRepo, job, {:ok, :done})

      %Job{
        done_at: done_at,
        attempted_at: attempted_at,
        attempted_by: attempted_by,
        attempts: attempts
      } = TestRepo.reload(job)

      refute is_nil(done_at)
      refute is_nil(attempted_at)
      assert attempted_by == Atom.to_string(Node.self())
      assert attempts == 1
      assert done_at == attempted_at
    end

    test "when a job failed, persists the job as failed and record the error" do
      job = insert!(:failure_job, scope: Queuetopia.TestQueuetopia.scope())

      _ = Jobs.persist_result!(TestRepo, job, {:error, "error"})

      %Job{} = job = TestRepo.reload(job)
      assert job.done_at == nil
      refute job.attempted_at == nil
      assert job.attempted_by == Atom.to_string(Node.self())
      assert job.attempts == 1
      assert job.error == "error"
    end

    test "when a job returns an unexpected_response, persists the job as failed and record the response" do
      job = insert!(:failure_job, scope: Queuetopia.TestQueuetopia.scope())

      _ = Jobs.persist_result!(TestRepo, job, "unexpected_response")

      %Job{} = job = TestRepo.reload(job)
      assert job.done_at == nil
      refute job.attempted_at == nil
      assert job.attempted_by == Atom.to_string(Node.self())
      assert job.attempts == 1
      assert job.error == "\"unexpected_response\""
    end

    test "when handle_failed_job/1 is defined by the performer" do
      %{id: id} =
        job =
        insert!(:failure_job,
          scope: Queuetopia.TestQueuetopiaWithHandleFailedJob |> to_string()
        )

      _ = Jobs.persist_result!(TestRepo, job, {:error, "error"})

      %Job{} = job = TestRepo.reload(job)
      assert job.done_at == nil
      refute job.attempted_at == nil
      assert job.attempted_by == Atom.to_string(Node.self())
      assert job.attempts == 1

      assert_receive {:job, %Job{id: ^id, done_at: nil, attempted_at: %DateTime{}, attempts: 1}},
                     100
    end

    test "by default, backoff is exponential for retry" do
      job =
        insert!(:failure_job,
          scope: Queuetopia.TestQueuetopia.scope(),
          max_backoff: 10 * 60 * 1_000
        )

      [2_000, 3_000, 5_000, 9_000, 17_000]
      |> Enum.each(fn backoff ->
        job = TestRepo.reload(job)

        Jobs.persist_result!(TestRepo, job, {:error, "error"})

        %Job{
          done_at: nil,
          attempted_at: attempted_at,
          next_attempt_at: next_attempt_at
        } = TestRepo.reload(job)

        assert :eq =
                 DateTime.compare(
                   next_attempt_at,
                   DateTime.add(attempted_at, backoff, :millisecond)
                 )
      end)
    end

    test "applies the backoff defined by the performer" do
      %{attempted_at: attempted_at} =
        job =
        insert!(:failure_job,
          scope: Queuetopia.TestQueuetopiaWithBackoff |> to_string(),
          attempted_at: utc_now() |> DateTime.truncate(:second)
        )

      Jobs.persist_result!(TestRepo, job, {:error, "error"})

      %{next_attempt_at: next_attempt_at} = job = TestRepo.reload(job)

      backoff = Queuetopia.TestQueuetopiaWithBackoff.Performer.backoff(job)
      assert backoff == 20 * 1_000

      assert_in_delta next_attempt_at |> DateTime.to_unix(),
                      DateTime.add(
                        attempted_at,
                        backoff,
                        :millisecond
                      )
                      |> DateTime.to_unix(),
                      1
    end

    test "for default backoff, limit to maximum backoff" do
      max_backoff = 2_000

      job =
        insert!(:failure_job, scope: Queuetopia.TestQueuetopia.scope(), max_backoff: max_backoff)

      _ = Jobs.persist_result!(TestRepo, job, {:error, "error"})

      %Job{
        done_at: nil,
        attempted_at: attempted_at,
        next_attempt_at: next_attempt_at
      } = TestRepo.reload(job)

      assert :eq =
               DateTime.compare(
                 next_attempt_at,
                 DateTime.add(attempted_at, max_backoff, :millisecond)
               )

      _ = Jobs.persist_result!(TestRepo, job, {:error, "error"})

      %Job{
        done_at: nil,
        attempted_at: attempted_at,
        next_attempt_at: next_attempt_at
      } = TestRepo.reload(job)

      assert :eq =
               DateTime.compare(
                 next_attempt_at,
                 DateTime.add(attempted_at, max_backoff, :millisecond)
               )
    end
  end

  describe "paginate_jobs/2" do
    test "returns a list of the jobs" do
      %{id: id} = insert!(:job)

      assert %{data: [%Job{id: ^id}], page_size: 100, page_number: 1, total: 1} =
               Jobs.paginate_jobs(TestRepo, 100, 1)
    end

    test "order_by" do
      %{id: id1} = insert!(:job, sequence: 1)
      %{id: id2} = insert!(:job, sequence: 2)

      assert %{data: [%{id: ^id2}, %{id: ^id1}]} = Jobs.paginate_jobs(TestRepo, 100, 1)

      assert %{data: [%{id: ^id1}, %{id: ^id2}]} =
               Jobs.paginate_jobs(TestRepo, 100, 1, order_by_fields: [asc: :sequence])
    end

    test "filters" do
      insert!(:job, done_at: utc_now())

      assert %{data: [], total: 0} =
               Jobs.paginate_jobs(TestRepo, 100, 1, filters: [available?: true])

      insert!(:job, attempts: 3, max_attempts: 3)

      assert %{data: [], total: 0} =
               Jobs.paginate_jobs(TestRepo, 100, 1, filters: [available?: true])

      %{id: id} = job = insert!(:job)

      [
        [id: job.id],
        [scope: job.scope],
        [queue: job.queue],
        [action: job.action],
        [available?: true]
      ]
      |> Enum.each(fn filter ->
        assert %{data: [%{id: ^id}], total: 1} =
                 Jobs.paginate_jobs(TestRepo, 100, 1, filters: filter)
      end)

      [
        [id: uuid()],
        [scope: "wrong"],
        [queue: "wrong"],
        [action: "wrong"]
      ]
      |> Enum.each(fn filter ->
        assert %{data: [], total: 0} = Jobs.paginate_jobs(TestRepo, 100, 1, filters: filter)
      end)
    end

    test "search_query" do
      %{id: id} = job = insert!(:job, params: %{a: "param_a"})

      [job.scope, job.queue, job.action, "param_a"]
      |> Enum.each(fn search_query ->
        assert %{data: [%{id: ^id}], total: 1} =
                 Jobs.paginate_jobs(TestRepo, 100, 1, search_query: search_query)
      end)

      assert %{data: [], total: 0} = Jobs.paginate_jobs(TestRepo, 100, 1, search_query: "wrong")
    end
  end

  describe "list_jobs/2" do
    test "returns a list of the jobs" do
      %{id: id} = insert!(:job)

      assert [%Job{id: ^id}] = Jobs.list_jobs(TestRepo)
    end

    test "order_by" do
      %{id: id1} = insert!(:job, sequence: 1)
      %{id: id2} = insert!(:job, sequence: 2)

      assert [%{id: ^id2}, %{id: ^id1}] = Jobs.list_jobs(TestRepo)

      assert [%{id: ^id1}, %{id: ^id2}] =
               Jobs.list_jobs(TestRepo, order_by_fields: [asc: :sequence])
    end

    test "filters" do
      insert!(:job, done_at: utc_now())

      assert Jobs.list_jobs(TestRepo, filters: [available?: true]) == []

      insert!(:job, attempts: 1, max_attempts: 1)

      assert Jobs.list_jobs(TestRepo, filters: [available?: true]) == []

      %{id: id} = job = insert!(:job)

      [
        [id: job.id],
        [scope: job.scope],
        [queue: job.queue],
        [action: job.action],
        [available?: true]
      ]
      |> Enum.each(fn filter ->
        assert [%{id: ^id}] = Jobs.list_jobs(TestRepo, filters: filter)
      end)

      [
        [id: uuid()],
        [scope: "wrong"],
        [queue: "wrong"],
        [action: "wrong"]
      ]
      |> Enum.each(fn filter ->
        assert Jobs.list_jobs(TestRepo, filters: filter) == []
      end)
    end

    test "search_query" do
      %{id: id} = job = insert!(:job, params: %{a: "param_a"})

      [job.scope, job.queue, job.action, "param_a"]
      |> Enum.each(fn search_query ->
        assert [%{id: ^id}] = Jobs.list_jobs(TestRepo, search_query: search_query)
      end)

      assert Jobs.list_jobs(TestRepo, search_query: "wrong") == []
    end
  end

  describe "cleanup_completed_jobs/3" do
    test "deletes old completed jobs" do
      scope = "test_scope"

      old_job = insert!(:job, scope: scope, done_at: utc_now() |> add(-8, :day))
      recent_job = insert!(:job, scope: scope, done_at: utc_now() |> add(-6, :day))
      pending_job = insert!(:job, scope: scope, done_at: nil)

      assert {1, nil} = Jobs.cleanup_completed_jobs(TestRepo, scope)

      assert is_nil(TestRepo.get(Job, old_job.id))
      assert TestRepo.get(Job, recent_job.id)
      assert TestRepo.get(Job, pending_job.id)
    end

    test "respects custom retention" do
      scope = "test_scope"

      old_job = insert!(:job, scope: scope, done_at: utc_now() |> add(-3, :day))

      assert {1, nil} = Jobs.cleanup_completed_jobs(TestRepo, scope, {2, :day})
      assert is_nil(TestRepo.get(Job, old_job.id))
    end

    test "only touches own scope" do
      old_job_a = insert!(:job, scope: "a", done_at: utc_now() |> add(-8, :day))
      old_job_b = insert!(:job, scope: "b", done_at: utc_now() |> add(-8, :day))

      assert {1, nil} = Jobs.cleanup_completed_jobs(TestRepo, "a")

      assert is_nil(TestRepo.get(Job, old_job_a.id))
      assert TestRepo.get(Job, old_job_b.id)
    end
  end
end
