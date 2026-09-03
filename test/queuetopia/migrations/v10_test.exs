defmodule Queuetopia.Migrations.V10Test do
  use Queuetopia.DataCase

  alias Queuetopia.Migrations.V10
  alias Queuetopia.PendingQueues.PendingQueue

  defp unique_scope, do: "scope_#{System.unique_integer([:positive])}"

  defp pending_queues(scope) do
    PendingQueue
    |> where([pq], pq.scope == ^scope)
    |> TestRepo.all()
    |> Enum.sort_by(& &1.queue)
  end

  defp truncate(datetime), do: DateTime.truncate(datetime, :second)

  describe "backfill/1" do
    test "inserts one row per queue holding pending jobs, at the head job's scheduled_at" do
      scope = unique_scope()
      head_at = utc_now() |> add(60)

      %{queue: queue_1} = insert!(:job, scope: scope, scheduled_at: head_at)
      insert!(:job, scope: scope, queue: queue_1, scheduled_at: head_at |> add(3600))
      %{queue: queue_2} = insert!(:job, scope: scope, scheduled_at: head_at)

      assert :ok = V10.backfill(TestRepo)

      expected_at = truncate(head_at)

      assert [
               %PendingQueue{queue: ^queue_1, next_performable_at: ^expected_at},
               %PendingQueue{queue: ^queue_2, next_performable_at: ^expected_at}
             ] = pending_queues(scope) |> Enum.sort_by(&(&1.queue == queue_2))
    end

    test "ignores done and exhausted jobs" do
      scope = unique_scope()
      insert!(:done_job, scope: scope)
      insert!(:job, scope: scope, attempts: 20, max_attempts: 20)

      assert :ok = V10.backfill(TestRepo)

      assert [] = pending_queues(scope)
    end

    test "a job in backoff is pending at its next_attempt_at" do
      scope = unique_scope()
      next_attempt_at = utc_now() |> add(3600)

      insert!(:job, scope: scope, scheduled_at: utc_now(), next_attempt_at: next_attempt_at)

      assert :ok = V10.backfill(TestRepo)

      expected_at = truncate(next_attempt_at)
      assert [%PendingQueue{next_performable_at: ^expected_at}] = pending_queues(scope)
    end

    test "keeps the scopes apart" do
      scope_1 = unique_scope()
      scope_2 = unique_scope()
      %{queue: queue} = insert!(:job, scope: scope_1)
      insert!(:job, scope: scope_2, queue: queue)

      assert :ok = V10.backfill(TestRepo)

      assert [%PendingQueue{scope: ^scope_1, queue: ^queue}] = pending_queues(scope_1)
      assert [%PendingQueue{scope: ^scope_2, queue: ^queue}] = pending_queues(scope_2)
    end

    test "is idempotent" do
      scope = unique_scope()
      insert!(:job, scope: scope)

      assert :ok = V10.backfill(TestRepo)
      [row] = pending_queues(scope)

      assert :ok = V10.backfill(TestRepo)
      assert [^row] = pending_queues(scope)
    end

    test "brings an existing row forward to the head job's time" do
      scope = unique_scope()
      %{queue: queue, scheduled_at: scheduled_at} = insert!(:job, scope: scope)

      build(:pending_queue,
        scope: scope,
        queue: queue,
        next_performable_at: scheduled_at |> add(3600) |> truncate()
      )
      |> TestRepo.insert!()

      assert :ok = V10.backfill(TestRepo)

      expected_at = truncate(scheduled_at)
      assert [%PendingQueue{next_performable_at: ^expected_at}] = pending_queues(scope)
    end

    test "never postpones an existing row" do
      scope = unique_scope()
      %{queue: queue, scheduled_at: scheduled_at} = insert!(:job, scope: scope)
      earlier_at = scheduled_at |> add(-3600) |> truncate()

      build(:pending_queue, scope: scope, queue: queue, next_performable_at: earlier_at)
      |> TestRepo.insert!()

      assert :ok = V10.backfill(TestRepo)

      assert [%PendingQueue{next_performable_at: ^earlier_at}] = pending_queues(scope)
    end
  end
end
