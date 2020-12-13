defmodule Queuetopia.Test.AssertionsTest do
  use Queuetopia.DataCase
  import Queuetopia.Test.Assertions

  describe "assert_job_created/1" do
    test "when the job has just been created" do
      scope = Queuetopia.TestQueuetopia.scope()
      queuetopia = Module.safe_concat([scope])

      Factory.insert(:job, scope: scope)

      assert_job_created(queuetopia)
    end

    test "when the job has not been created" do
      assert_raise ExUnit.AssertionError, fn ->
        job = Factory.params_for(:job, scope: Queuetopia.TestQueuetopia.scope())
        assert_job_created(Queuetopia.TestQueuetopia, job)
      end
    end
  end

  describe "assert_job_created/2 for a specific queue" do
    test "when the job has just been created" do
      job = Factory.insert(:job, scope: Queuetopia.TestQueuetopia.scope())

      assert_job_created(Queuetopia.TestQueuetopia, job.queue)
    end

    test "when the job has not been created for the queue" do
      assert_raise ExUnit.AssertionError, fn ->
        Factory.insert(:job, scope: Queuetopia.TestQueuetopia.scope())

        assert_job_created(Queuetopia.TestQueuetopia, "sample queue")
      end
    end

    test "when the job has not been created at all" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, "sample_queue")
      end
    end
  end

  describe "assert_job_created/2 for a specific job" do
    test "when the job has just been created" do
      %{id: job_id} =
        Factory.insert(:job, scope: Queuetopia.TestQueuetopia.scope(), params: %{b: 1, c: 2})

      job = Queuetopia.TestQueuetopia.repo().get(Queuetopia.Jobs.Job, job_id)
      assert_job_created(Queuetopia.TestQueuetopia, job)
      assert_job_created(Queuetopia.TestQueuetopia, %{params: %{"c" => 2}})
      assert_job_created(Queuetopia.TestQueuetopia, %{action: job.action, params: %{"c" => 2}})

      assert_raise ExUnit.AssertionError, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, %{params: %{c: 10}})
        assert_job_created(Queuetopia.TestQueuetopia, %{action: 10, params: %{"c" => 2}})
      end
    end

    test "when the job has not been created" do
      assert_raise ExUnit.AssertionError, fn ->
        job = Factory.params_for(:job, scope: Queuetopia.TestQueuetopia.scope())

        assert_job_created(Queuetopia.TestQueuetopia, job)
      end
    end
  end

  describe "assert_job_created/3 for a specific job and a specific queue" do
    test "when the job has just been created" do
      %{id: job_id} =
        Factory.insert(:job, scope: Queuetopia.TestQueuetopia.scope(), params: %{b: 1, c: 2})

      job = Queuetopia.TestQueuetopia.repo().get(Queuetopia.Jobs.Job, job_id)
      assert_job_created(Queuetopia.TestQueuetopia, job.queue, job)
      assert_job_created(Queuetopia.TestQueuetopia, job.queue, %{params: %{"c" => 2}})

      assert_raise ExUnit.AssertionError, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, job.queue, %{params: %{"c" => 10}})

        assert_job_created(Queuetopia.TestQueuetopia, job.queue, %{
          action: 10,
          params: %{"c" => 2}
        })
      end
    end

    test "when the job has not been created for the queue" do
      assert_raise ExUnit.AssertionError, fn ->
        job = Factory.insert(:job, scope: Queuetopia.TestQueuetopia.scope())

        assert_job_created(Queuetopia.TestQueuetopia, "sample queue", job)
      end
    end

    test "when the job has not been created at all" do
      assert_raise ExUnit.AssertionError, fn ->
        job = Factory.params_for(:job, scope: Queuetopia.TestQueuetopia.scope())

        assert_job_created(Queuetopia.TestQueuetopia, "sample_queue", job)
      end
    end
  end
end
