defmodule QueuetopiaTest do
  use Queuetopia.DataCase
  alias Queuetopia.{TestQueuetopia, TestQueuetopia_2}
  alias Queuetopia.Jobs.Job

  test "multiple instances can coexist" do
    start_supervised!(Queuetopia.TestQueuetopia)
    start_supervised!(Queuetopia.TestQueuetopia_2)

    :sys.get_state(Queuetopia.TestQueuetopia.Scheduler)
    :sys.get_state(Queuetopia.TestQueuetopia_2.Scheduler)
  end

  describe "create_job/4" do
    test "set the performer and the scope and creates a job in the corresponding repo" do
      %{queue: queue, action: action, params: params} = Factory.params_for(:job)

      assert {:ok, %Job{id: id, performer: performer, scope: scope}} =
               TestQueuetopia.create_job(queue, action, params)

      assert performer == TestQueuetopia.performer()
      assert scope == TestQueuetopia.scope()

      refute is_nil(TestQueuetopia.repo().get(Job, id))
    end

    test "when options are set" do
      %{
        queue: queue,
        action: action,
        params: params,
        timeout: timeout,
        max_backoff: max_backoff,
        max_attempts: max_attempts
      } = Factory.params_for(:job)

      assert {:ok,
              %Job{
                queue: ^queue,
                action: ^action,
                params: ^params,
                timeout: ^timeout,
                max_backoff: ^max_backoff,
                max_attempts: ^max_attempts
              }} =
               TestQueuetopia.create_job(queue, action, params,
                 timeout: timeout,
                 max_backoff: max_backoff,
                 max_attempts: max_attempts
               )
    end

    test "when timing options are not set, takes the default job timing options" do
      timeout = Job.default_timeout()
      max_backoff = Job.default_max_backoff()
      max_attempts = Job.default_max_attempts()

      %{queue: queue, action: action, params: params} = Factory.params_for(:job)

      assert {:ok,
              %Job{
                timeout: ^timeout,
                max_backoff: ^max_backoff,
                max_attempts: ^max_attempts
              }} = TestQueuetopia_2.create_job(queue, action, params)
    end

    test "when the queue is running and the job succeeds, sends a poll request to the scheduler" do
      next_poll_in = 5_000

      start_supervised!({Queuetopia.TestQueuetopia, [poll_interval: next_poll_in]})

      %{queue: queue, action: action, params: params} = Factory.params_for(:success_job)

      assert {:ok, %Job{id: id, performer: performer, scope: scope}} =
               TestQueuetopia.create_job(queue, action, params)

      assert_receive :ok, 1_000
    end
  end

  describe "send_poll/0" do
    test "when the scheduler is up, no matter if the process inbox is empty or not returns :ok" do
      next_poll_in = 5_000

      start_supervised!({Queuetopia.TestQueuetopia, [poll_interval: next_poll_in]})

      scheduler_pid = Process.whereis(TestQueuetopia.Scheduler)

      assert :ok = TestQueuetopia.send_poll()

      {:messages, messages} = Process.info(scheduler_pid, :messages)
      assert length(messages) == 1

      assert :ok = TestQueuetopia.send_poll()

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "when the scheduler is down, returns an error tuple" do
      assert {:error, "scheduler down"} == TestQueuetopia.send_poll()
    end
  end
end
