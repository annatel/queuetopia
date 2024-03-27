defmodule Queuetopia.Test.AssertionsTest do
  use Queuetopia.DataCase

  import Queuetopia.Test.Assertions

  describe "jobs_created/1" do
    test "when the job is found" do
      insert!(:job, scope: Queuetopia.TestQueuetopia.scope())
      assert [_] = jobs_created(Queuetopia.TestQueuetopia)
    end

    test "multiple jobs" do
      insert!(:job, scope: Queuetopia.TestQueuetopia.scope())
      insert!(:job, scope: Queuetopia.TestQueuetopia.scope())
      assert [_, _] = jobs_created(Queuetopia.TestQueuetopia)
    end

    test "when no job is found" do
      assert [] = jobs_created(Queuetopia.TestQueuetopia)
    end
  end

  describe "assert_job_created/1" do
    test "when the job is found" do
      insert!(:job, scope: Queuetopia.TestQueuetopia.scope())
      assert_job_created(Queuetopia.TestQueuetopia)
    end

    test "count option" do
      insert!(:job, scope: Queuetopia.TestQueuetopia.scope())

      message =
        %ExUnit.AssertionError{
          message: "Expected 2 jobs, got 1"
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, 2)
      end
    end

    test "when the job is not found" do
      message =
        %ExUnit.AssertionError{message: "Expected 1 job, got 0"}
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia)
      end
    end
  end

  describe "assert_job_recorded/2" do
    test "when the job is found" do
      job =
        insert!(:job,
          scope: Queuetopia.TestQueuetopia.scope(),
          params: %{"a" => 1, "b" => 2}
        )

      insert!(:job, scope: Queuetopia.TestQueuetopia.scope(), params: %{"c" => 3})

      assert_job_created(Queuetopia.TestQueuetopia, job)
      assert_job_created(Queuetopia.TestQueuetopia, %{queue: job.queue})
      assert_job_created(Queuetopia.TestQueuetopia, %{params: %{"a" => 1}})
      assert_job_created(Queuetopia.TestQueuetopia, %{action: job.action})
    end

    test "when the job is not found" do
      job =
        insert!(:job,
          scope: Queuetopia.TestQueuetopia.scope(),
          params: %{"a" => 1}
        )

      expected_attributes = %{queue: "queue", scope: job.scope}
      message =
        %ExUnit.AssertionError{
          message:
            "Expected 1 job with attributes #{inspect(expected_attributes)}, got 0."
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, %{queue: "queue"})
      end

      expected_attributes = %{action: "action", scope: job.scope}
      message =
        %ExUnit.AssertionError{
          message:
            "Expected 1 job with attributes #{inspect(expected_attributes)}, got 0."
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, %{action: "action"})
      end
    end

    test "when params is specified but not match" do
      job =
        insert!(:job,
          scope: Queuetopia.TestQueuetopia.scope(),
          params: %{"a" => 1}
        )

      expected_attributes = %{params: %{"b" => 2}, scope: job.scope}
      message =
        %ExUnit.AssertionError{
          message:
            "Expected 1 job with attributes #{inspect(expected_attributes)}, got 0."
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, %{params: %{"b" => 2}})
      end
    end

    test "with params and count" do
      job =
        insert!(:job,
          scope: Queuetopia.TestQueuetopia.scope(),
          params: %{"a" => 1}
        )

      insert!(:job,
        scope: Queuetopia.TestQueuetopia.scope(),
        params: %{"a" => 1}
      )

      expected_attributes = %{params: %{"a" => 1}, scope: job.scope}
      message =
        %ExUnit.AssertionError{
          message:
            "Expected 1 job with attributes #{inspect(expected_attributes)}, got 2."
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, 1, %{params: %{"a" => 1}})
      end
    end
  end

  describe "refute_job_created/1" do
    test "when the job is not created" do
      refute_job_created(Queuetopia.TestQueuetopia)
    end

    test "when the job is created" do
      insert!(:job, scope: Queuetopia.TestQueuetopia.scope())

      message =
        %ExUnit.AssertionError{
          message: "Expected 0 job, got 1"
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia)
      end
    end
  end

  describe "refute_job_created/2" do
    test "when the job is not created" do
      refute_job_created(Queuetopia.TestQueuetopia, %{queue: "queue"})
    end

    test "when the job is created" do
      job = insert!(:job, scope: Queuetopia.TestQueuetopia.scope(), params: %{"a" => 1})

      expected_attributes = %{queue: job.queue, scope: job.scope}
      message =
        %ExUnit.AssertionError{
          message:
            "Expected 0 job with attributes #{inspect(expected_attributes)}, got 1."
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia, %{queue: job.queue})
      end

      expected_attributes = %{action: job.action, scope: job.scope}
      message =
        %ExUnit.AssertionError{
          message:
            "Expected 0 job with attributes #{inspect(expected_attributes)}, got 1."
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia, %{action: job.action})
      end

      expected_attributes = %{params: job.params, scope: job.scope}
      message =
        %ExUnit.AssertionError{
          message:
            "Expected 0 job with attributes #{inspect(expected_attributes)}, got 1."
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia, %{params: %{"a" => 1}})
      end
    end
  end
end
