defmodule Queuetopia.Test.AssertionsTest do
  use Queuetopia.DataCase
  import Queuetopia.Test.Assertions

  describe "assert_job_created/0" do
    test "when the job has just been created" do
      scope = Queuetopia.TestQueuetopia.scope()
      queue = [scope] |> Module.safe_concat()

      job = Factory.insert(:job, scope: scope)

      assert_job_created(queue, Map.from_struct(job))
    end

    test "when the job has not been created" do
      assert_raise ExUnit.AssertionError, fn ->
        scope = Queuetopia.TestQueuetopia.scope()
        queue = [scope] |> Module.safe_concat()

        job_params = Factory.params_for(:job)

        assert_job_created(queue, job_params)
      end
    end
  end
end
