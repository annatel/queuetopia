defmodule Queuetopia.Test.AssertionsTest do
  use Queuetopia.DataCase
  import Queuetopia.Test.Assertions

  describe "assert_job_created/1" do
    test "when the job has just been created" do
      scope = Queuetopia.TestQueuetopia.scope()
      queuetopia = Module.safe_concat([scope])

      Factory.insert!(:job, scope: scope)

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
      job = Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope())

      assert_job_created(Queuetopia.TestQueuetopia, job.queue)
    end

    test "when the job has not been created for the queue" do
      message =
        %ExUnit.AssertionError{
          message: """
          Expected a job matching:

          %{queue: "sample_queue", scope: #{inspect(Queuetopia.TestQueuetopia.scope())}}

          Found job: nil
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope())

        assert_job_created(Queuetopia.TestQueuetopia, "sample_queue")
      end
    end

    test "when the job has not been created at all" do
      message =
        %ExUnit.AssertionError{
          message: """
          Expected a job matching:

          %{queue: "sample_queue", scope: #{inspect(Queuetopia.TestQueuetopia.scope())}}

          Found job: nil
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, "sample_queue")
      end
    end
  end

  describe "assert_job_created/2 for a specific job" do
    test "when the job has just been created" do
      Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope(), params: %{a: 1})

      %{id: job_id} =
        Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope(), params: %{b: 1, c: 2})

      job = Queuetopia.TestQueuetopia.repo().get(Queuetopia.Queue.Job, job_id)
      assert_job_created(Queuetopia.TestQueuetopia, job)
      assert_job_created(Queuetopia.TestQueuetopia, %{params: %{"c" => 2}})
      assert_job_created(Queuetopia.TestQueuetopia, %{action: job.action, params: %{"c" => 2}})

      message =
        %ExUnit.AssertionError{
          message: """
          Expected a job matching:

          %{params: %{c: 10}}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, %{params: %{c: 10}})
      end

      message =
        %ExUnit.AssertionError{
          message: """
          Expected a job matching:

          %{action: 10, params: %{"c" => 2}}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
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
        Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope(), params: %{b: 1, c: 2})

      job = Queuetopia.TestQueuetopia.repo().get(Queuetopia.Queue.Job, job_id)
      assert_job_created(Queuetopia.TestQueuetopia, job.queue, job)
      assert_job_created(Queuetopia.TestQueuetopia, job.queue, %{params: %{"c" => 2}})

      message =
        %ExUnit.AssertionError{
          message: """
          Expected a job matching:

          %{action: 10, params: %{"c" => 2}}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, %{action: 10, params: %{"c" => 2}})
      end

      message =
        %ExUnit.AssertionError{
          message: """
          Expected a job matching:

          %{action: 10, params: %{"c" => 2}}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        assert_job_created(Queuetopia.TestQueuetopia, job.queue, %{
          action: 10,
          params: %{"c" => 2}
        })
      end
    end

    test "when the job has not been created for the queue" do
      assert_raise ExUnit.AssertionError, fn ->
        job = Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope())

        assert_job_created(Queuetopia.TestQueuetopia, "sample_queue", job)
      end
    end

    test "when the job has not been created at all" do
      assert_raise ExUnit.AssertionError, fn ->
        job = Factory.params_for(:job, scope: Queuetopia.TestQueuetopia.scope())

        assert_job_created(Queuetopia.TestQueuetopia, "sample_queue", job)
      end
    end
  end

  describe "refute_job_created/1" do
    test "when the job is not created" do
      refute_job_created(Queuetopia.TestQueuetopia)
    end

    test "when the job is created" do
      job = Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope())

      message =
        %ExUnit.AssertionError{
          message: """
          Expected no job matching:

          %{scope: "Elixir.Queuetopia.TestQueuetopia"}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia)
      end
    end
  end

  describe "refute_job_created/2 with queue" do
    test "when the job is not created" do
      refute_job_created(Queuetopia.TestQueuetopia, "queue_name")
    end

    test "when the job is created" do
      job = Factory.insert!(:job, scope: Queuetopia.TestQueuetopia.scope(), queue: "queue_name")

      message =
        %ExUnit.AssertionError{
          message: """
          Expected no job matching:

          %{queue: "queue_name", scope: "Elixir.Queuetopia.TestQueuetopia"}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia, "queue_name")
      end
    end
  end

  describe "refute_job_created/2 with job" do
    test "when the job is not created" do
      refute_job_created(Queuetopia.TestQueuetopia, %{action: "foo", params: %{"c" => 2}})
    end

    test "when the job is created" do
      job =
        Factory.insert!(:job,
          scope: Queuetopia.TestQueuetopia.scope(),
          queue: "queue_name",
          action: "foo",
          params: %{"c" => 2}
        )

      message =
        %ExUnit.AssertionError{
          message: """
          Expected no job matching:

          %{action: "foo", params: %{"c" => 2}}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia, %{action: "foo", params: %{"c" => 2}})
      end
    end
  end

  describe "refute_job_created/3" do
    test "when the job is not created" do
      refute_job_created(Queuetopia.TestQueuetopia, "queue_name", %{
        action: "foo",
        params: %{"c" => 2}
      })
    end

    test "when the job is created" do
      job =
        Factory.insert!(:job,
          scope: Queuetopia.TestQueuetopia.scope(),
          queue: "queue_name",
          action: "foo",
          params: %{"c" => 2}
        )

      message =
        %ExUnit.AssertionError{
          message: """
          Expected no job matching:

          %{action: "foo", params: %{"c" => 2}}

          Found job: #{inspect(job, pretty: true)}
          """
        }
        |> ExUnit.AssertionError.message()

      assert_raise ExUnit.AssertionError, message, fn ->
        refute_job_created(Queuetopia.TestQueuetopia, "queue_name", %{
          action: "foo",
          params: %{"c" => 2}
        })
      end
    end
  end
end
