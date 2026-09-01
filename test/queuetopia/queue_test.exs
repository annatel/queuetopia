defmodule Queuetopia.QueueTest do
  use Queuetopia.DataCase

  alias Queuetopia.Queue
  alias Queuetopia.Queue.Job
  alias Queuetopia.Queue.Lock
  alias Queuetopia.Queue.PendingQueue

  describe "list_available_pending_queues/1" do
    test "returns the scoped queues whose next_runnable_at is reached" do
      %{queue: queue, scope: scope} = insert_pending_job!(:job)

      assert [^queue] = Queue.list_available_pending_queues(TestRepo, scope)
    end

    test "don't list queues whose next_runnable_at is not reached yet" do
      %{scope: scope} = insert_pending_job!(:job, scheduled_at: utc_now() |> add(3600))

      assert [] = Queue.list_available_pending_queues(TestRepo, scope)
    end

    test "don't list queues without pending row (done or exhausted jobs)" do
      %{scope: scope_1} = insert!(:done_job)

      %{scope: scope_2} =
        insert!(:job, scheduled_at: utc_now() |> add(-3600), attempts: 5, max_attempts: 5)

      assert [] = Queue.list_available_pending_queues(TestRepo, scope_1)
      assert [] = Queue.list_available_pending_queues(TestRepo, scope_2)
    end

    test "when limit is given, returns only the specified number of rows from the result set" do
      %{scope: scope} = insert_pending_job!(:job)
      insert_pending_job!(:job, scope: scope)

      assert [_] = Queue.list_available_pending_queues(TestRepo, scope, limit: 1)
    end

    test "when a queue is locked" do
      %{queue: queue_1, scope: scope_1} = insert_pending_job!(:job)
      _ = insert!(:lock, queue: queue_1, scope: scope_1)

      assert [] = Queue.list_available_pending_queues(TestRepo, scope_1)
    end

    test "there is no collision between two queues with the same name but in different scope" do
      %{queue: queue, scope: scope_1} = insert_pending_job!(:job)
      %{scope: scope_2} = insert_pending_job!(:job, queue: queue)

      _ = insert!(:lock, queue: queue, scope: scope_1)

      assert [] = Queue.list_available_pending_queues(TestRepo, scope_1)
      assert [^queue] = Queue.list_available_pending_queues(TestRepo, scope_2)
    end

    test "a new job on a queue in backoff makes it listed until the queue is refreshed" do
      %{queue: queue, scope: scope} =
        job =
        insert_pending_job!(:failure_job,
          scope: Queuetopia.TestQueuetopia.scope(),
          max_backoff: 3_600_000
        )

      Queue.persist_result!(TestRepo, job, {:error, "error"})

      assert [] = Queue.list_available_pending_queues(TestRepo, scope)

      {:ok, _} =
        Queue.create_job(
          job_attrs(params_for(:job, scope: scope, queue: queue)),
          TestRepo
        )

      assert [^queue] = Queue.list_available_pending_queues(TestRepo, scope)

      Queue.refresh_pending_queue!(TestRepo, scope, queue)

      assert [] = Queue.list_available_pending_queues(TestRepo, scope)
    end
  end

  describe "claim_next_runnable_job/3" do
    test "claims the head runnable job and locks the queue" do
      %{id: id, queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now())
      insert!(:job, queue: queue, scope: scope, scheduled_at: utc_now() |> add(60))

      assert {:ok, %Job{id: ^id}} = Queue.claim_next_runnable_job(TestRepo, scope, queue)

      assert %Lock{locked_until: locked_until, locked_at: locked_at} =
               TestRepo.get_by(Lock, scope: scope, queue: queue)

      assert locked_until ==
               locked_at |> DateTime.add(6_000, :millisecond) |> DateTime.truncate(:second)
    end

    test "when the queue has an expired lock, still returns an error" do
      %{queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now())
      insert!(:expired_lock, scope: scope, queue: queue)

      assert {:error, :locked} = Queue.claim_next_runnable_job(TestRepo, scope, queue)
    end

    test "when the queue is already locked, returns an error and claims nothing" do
      %{queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now())
      insert!(:lock, scope: scope, queue: queue)

      assert {:error, :locked} = Queue.claim_next_runnable_job(TestRepo, scope, queue)
    end

    test "when the head job is not runnable yet, returns an error without locking the queue" do
      %{queue: queue, scope: scope} = insert!(:job, scheduled_at: utc_now() |> add(3600))

      assert {:error, :no_runnable_job} = Queue.claim_next_runnable_job(TestRepo, scope, queue)
      assert is_nil(TestRepo.get_by(Lock, scope: scope, queue: queue))
    end

    test "when the queue has no pending job, returns an error without locking the queue" do
      %{queue: queue, scope: scope} = insert!(:done_job)

      assert {:error, :no_runnable_job} = Queue.claim_next_runnable_job(TestRepo, scope, queue)
      assert is_nil(TestRepo.get_by(Lock, scope: scope, queue: queue))
    end
  end

  describe "get_next_runnable_job/2" do
    test "returns the next pending job for a given scoped queue" do
      %{queue: queue_1, scope: scope_1} = insert!(:done_job)
      %{id: id_1} = insert!(:job, queue: queue_1, scope: scope_1)

      %{id: id_2, queue: queue_2} = insert!(:job, scope: scope_1)

      %{id: id_3, queue: queue_3, scope: scope_2} = insert!(:job)

      assert %Job{id: ^id_1} = Queue.get_next_runnable_job(TestRepo, scope_1, queue_1)
      assert %Job{id: ^id_2} = Queue.get_next_runnable_job(TestRepo, scope_1, queue_2)
      assert %Job{id: ^id_3} = Queue.get_next_runnable_job(TestRepo, scope_2, queue_3)
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

      assert %Job{id: ^id} = Queue.get_next_runnable_job(TestRepo, scope, queue)
    end

    test "for multiple jobs with the same scheduled_at, preseance by sequence" do
      utc_now = utc_now()

      %{id: id_1, scope: scope, queue: queue} = insert!(:job, scheduled_at: utc_now, sequence: 1)

      insert!(:job, scope: scope, queue: queue, scheduled_at: utc_now, sequence: 2)

      assert %Job{id: ^id_1} = Queue.get_next_runnable_job(TestRepo, scope, queue)
    end

    test "when the queue is empty, returns nil" do
      %{queue: queue, scope: scope} = insert!(:done_job)

      assert is_nil(Queue.get_next_runnable_job(TestRepo, scope, queue))
    end

    test "when the queue does not exist, returns nil" do
      %{queue: queue, scope: scope} = params_for(:job)

      assert is_nil(Queue.get_next_runnable_job(TestRepo, scope, queue))
    end

    test "when the next pending job is scheduled for later" do
      %Job{queue: queue, scope: scope} =
        insert!(:job, scheduled_at: utc_now() |> add(3600, :second))

      assert is_nil(Queue.get_next_runnable_job(TestRepo, scope, queue))
    end

    test "when the next pending job next attempt is scheduled for now" do
      %Job{queue: queue, scope: scope, id: id} = insert!(:job, next_attempt_at: utc_now())

      assert %Job{id: ^id} = Queue.get_next_runnable_job(TestRepo, scope, queue)
    end

    test "when the next pending job next attempt is scheduled for later" do
      %Job{queue: queue, scope: scope} =
        insert!(:job, next_attempt_at: utc_now() |> add(3600, :second))

      assert is_nil(Queue.get_next_runnable_job(TestRepo, scope, queue))
    end

    test "when max job attempts is reached, returns nil" do
      %Job{queue: queue, scope: scope} =
        insert!(:job, next_attempt_at: utc_now(), attempts: 20, max_attempts: 20)

      assert is_nil(Queue.get_next_runnable_job(TestRepo, scope, queue))
    end
  end

  test "perform/1" do
    job = insert!(:success_job, scope: Queuetopia.TestQueuetopia.scope())
    assert Queue.perform(job) == :ok
  end

  describe "persist_result!/4" do
    test "when a job succeeded, persists the job as succeeded" do
      job = insert!(:success_job)

      _ = Queue.persist_result!(TestRepo, job, :ok)

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

      _ = Queue.persist_result!(TestRepo, job, {:ok, :done})

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

      _ = Queue.persist_result!(TestRepo, job, {:error, "error"})

      %Job{} = job = TestRepo.reload(job)
      assert job.done_at == nil
      refute job.attempted_at == nil
      assert job.attempted_by == Atom.to_string(Node.self())
      assert job.attempts == 1
      assert job.error == "error"
    end

    test "when a job returns an unexpected_response, persists the job as failed and record the response" do
      job = insert!(:failure_job, scope: Queuetopia.TestQueuetopia.scope())

      _ = Queue.persist_result!(TestRepo, job, "unexpected_response")

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

      _ = Queue.persist_result!(TestRepo, job, {:error, "error"})

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

        Queue.persist_result!(TestRepo, job, {:error, "error"})

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

      Queue.persist_result!(TestRepo, job, {:error, "error"})

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

      _ = Queue.persist_result!(TestRepo, job, {:error, "error"})

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

      _ = Queue.persist_result!(TestRepo, job, {:error, "error"})

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

  test "release_expired_locks/2" do
    %Lock{id: id, scope: scope} = insert!(:lock)
    %Lock{} = insert!(:expired_lock, scope: scope)

    assert all_locks(scope) |> Enum.count() == 2
    assert {1, nil} = Queue.release_expired_locks(TestRepo, scope)
    assert [%Lock{id: ^id}] = all_locks(scope)
  end

  test "unlock_queue/1 removes the queue's lock" do
    %Lock{id: id, queue: queue, scope: scope} = insert!(:lock)

    assert [%Lock{id: ^id}] = all_locks(scope)

    _ = Queue.unlock_queue(TestRepo, scope, queue)

    assert TestRepo.all(Lock) == []
  end

  describe "paginate_jobs/2" do
    test "returns a list of the jobs" do
      %{id: id} = insert!(:job)

      assert %{data: [%Job{id: ^id}], page_size: 100, page_number: 1, total: 1} =
               Queue.paginate_jobs(TestRepo, 100, 1)
    end

    test "order_by" do
      %{id: id1} = insert!(:job, sequence: 1)
      %{id: id2} = insert!(:job, sequence: 2)

      assert %{data: [%{id: ^id2}, %{id: ^id1}]} = Queue.paginate_jobs(TestRepo, 100, 1)

      assert %{data: [%{id: ^id1}, %{id: ^id2}]} =
               Queue.paginate_jobs(TestRepo, 100, 1, order_by_fields: [asc: :sequence])
    end

    test "filters" do
      insert!(:job, done_at: utc_now())

      assert %{data: [], total: 0} =
               Queue.paginate_jobs(TestRepo, 100, 1, filters: [available?: true])

      insert!(:job, attempts: 3, max_attempts: 3)

      assert %{data: [], total: 0} =
               Queue.paginate_jobs(TestRepo, 100, 1, filters: [available?: true])

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
                 Queue.paginate_jobs(TestRepo, 100, 1, filters: filter)
      end)

      [
        [id: uuid()],
        [scope: "wrong"],
        [queue: "wrong"],
        [action: "wrong"]
      ]
      |> Enum.each(fn filter ->
        assert %{data: [], total: 0} = Queue.paginate_jobs(TestRepo, 100, 1, filters: filter)
      end)
    end

    test "search_query" do
      %{id: id} = job = insert!(:job, params: %{a: "param_a"})

      [job.scope, job.queue, job.action, "param_a"]
      |> Enum.each(fn search_query ->
        assert %{data: [%{id: ^id}], total: 1} =
                 Queue.paginate_jobs(TestRepo, 100, 1, search_query: search_query)
      end)

      assert %{data: [], total: 0} = Queue.paginate_jobs(TestRepo, 100, 1, search_query: "wrong")
    end
  end

  describe "list_jobs/2" do
    test "returns a list of the jobs" do
      %{id: id} = insert!(:job)

      assert [%Job{id: ^id}] = Queue.list_jobs(TestRepo)
    end

    test "order_by" do
      %{id: id1} = insert!(:job, sequence: 1)
      %{id: id2} = insert!(:job, sequence: 2)

      assert [%{id: ^id2}, %{id: ^id1}] = Queue.list_jobs(TestRepo)

      assert [%{id: ^id1}, %{id: ^id2}] =
               Queue.list_jobs(TestRepo, order_by_fields: [asc: :sequence])
    end

    test "filters" do
      insert!(:job, done_at: utc_now())

      assert Queue.list_jobs(TestRepo, filters: [available?: true]) == []

      insert!(:job, attempts: 1, max_attempts: 1)

      assert Queue.list_jobs(TestRepo, filters: [available?: true]) == []

      %{id: id} = job = insert!(:job)

      [
        [id: job.id],
        [scope: job.scope],
        [queue: job.queue],
        [action: job.action],
        [available?: true]
      ]
      |> Enum.each(fn filter ->
        assert [%{id: ^id}] = Queue.list_jobs(TestRepo, filters: filter)
      end)

      [
        [id: uuid()],
        [scope: "wrong"],
        [queue: "wrong"],
        [action: "wrong"]
      ]
      |> Enum.each(fn filter ->
        assert Queue.list_jobs(TestRepo, filters: filter) == []
      end)
    end

    test "search_query" do
      %{id: id} = job = insert!(:job, params: %{a: "param_a"})

      [job.scope, job.queue, job.action, "param_a"]
      |> Enum.each(fn search_query ->
        assert [%{id: ^id}] = Queue.list_jobs(TestRepo, search_query: search_query)
      end)

      assert Queue.list_jobs(TestRepo, search_query: "wrong") == []
    end
  end

  describe "cleanup_completed_jobs/3" do
    test "deletes old completed jobs" do
      scope = "test_scope"

      old_job = insert!(:job, scope: scope, done_at: utc_now() |> add(-8, :day))
      recent_job = insert!(:job, scope: scope, done_at: utc_now() |> add(-6, :day))
      pending_job = insert!(:job, scope: scope, done_at: nil)

      assert {1, nil} = Queue.cleanup_completed_jobs(TestRepo, scope)

      assert is_nil(TestRepo.get(Job, old_job.id))
      assert TestRepo.get(Job, recent_job.id)
      assert TestRepo.get(Job, pending_job.id)
    end

    test "respects custom retention" do
      scope = "test_scope"

      old_job = insert!(:job, scope: scope, done_at: utc_now() |> add(-3, :day))

      assert {1, nil} = Queue.cleanup_completed_jobs(TestRepo, scope, {2, :day})
      assert is_nil(TestRepo.get(Job, old_job.id))
    end

    test "only touches own scope" do
      old_job_a = insert!(:job, scope: "a", done_at: utc_now() |> add(-8, :day))
      old_job_b = insert!(:job, scope: "b", done_at: utc_now() |> add(-8, :day))

      assert {1, nil} = Queue.cleanup_completed_jobs(TestRepo, "a")

      assert is_nil(TestRepo.get(Job, old_job_a.id))
      assert TestRepo.get(Job, old_job_b.id)
    end
  end

  describe "pending queues maintenance" do
    test "create_job registers the queue as pending, runnable at the job's scheduled_at" do
      params = params_for(:job)
      attrs = job_attrs(params)

      assert {:ok, %Job{}} = Queue.create_job(attrs, TestRepo)

      assert %PendingQueue{next_runnable_at: next_runnable_at} =
               get_pending_queue(params.scope, params.queue)

      assert DateTime.compare(next_runnable_at, DateTime.truncate(params.scheduled_at, :second)) ==
               :eq
    end

    test "create_job keeps the earliest next_runnable_at of the queue" do
      utc_now = utc_now() |> DateTime.truncate(:second)
      params = params_for(:job, scheduled_at: utc_now |> DateTime.add(3600))

      {:ok, _} = Queue.create_job(job_attrs(params), TestRepo)

      {:ok, _} =
        Queue.create_job(
          job_attrs(
            params_for(:job, queue: params.queue, scope: params.scope, scheduled_at: utc_now)
          ),
          TestRepo
        )

      {:ok, _} =
        Queue.create_job(
          job_attrs(
            params_for(:job,
              queue: params.queue,
              scope: params.scope,
              scheduled_at: utc_now |> DateTime.add(7200)
            )
          ),
          TestRepo
        )

      assert %PendingQueue{next_runnable_at: next_runnable_at} =
               get_pending_queue(params.scope, params.queue)

      assert DateTime.compare(next_runnable_at, utc_now) == :eq
    end

    test "a succeeded job moves next_runnable_at to the next job of the queue" do
      utc_now = utc_now() |> DateTime.truncate(:second)
      later = utc_now |> DateTime.add(3600)

      job = insert!(:success_job, scope: Queuetopia.TestQueuetopia.scope(), scheduled_at: utc_now)
      insert!(:job, scope: job.scope, queue: job.queue, scheduled_at: later)

      Queue.persist_result!(TestRepo, job, :ok)

      assert %PendingQueue{next_runnable_at: next_runnable_at} =
               get_pending_queue(job.scope, job.queue)

      assert DateTime.compare(next_runnable_at, later) == :eq
    end

    test "a succeeded last job removes the pending queue" do
      job = insert!(:success_job, scope: Queuetopia.TestQueuetopia.scope())

      Queue.persist_result!(TestRepo, job, :ok)

      assert is_nil(get_pending_queue(job.scope, job.queue))
    end

    test "a failed job pushes next_runnable_at to its next attempt" do
      job = insert!(:failure_job, scope: Queuetopia.TestQueuetopia.scope(), max_backoff: 60_000)

      Queue.persist_result!(TestRepo, job, {:error, "error"})

      %Job{next_attempt_at: next_attempt_at} = TestRepo.reload(job)

      assert %PendingQueue{next_runnable_at: next_runnable_at} =
               get_pending_queue(job.scope, job.queue)

      assert DateTime.compare(next_runnable_at, next_attempt_at) == :eq
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

  defp get_pending_queue(scope, queue) do
    PendingQueue
    |> Ecto.Query.where(scope: ^scope, queue: ^queue)
    |> TestRepo.one()
  end

  defp all_locks(scope) do
    Lock |> Ecto.Query.where(scope: ^scope) |> TestRepo.all()
  end
end
