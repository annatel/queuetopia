defmodule QueuetopiaTest do
  use Queuetopia.DataCase
  alias Queuetopia.{TestQueuetopia, TestQueuetopia_2}
  alias Queuetopia.Queue.Job

  setup do
    Application.put_env(:queuetopia, TestQueuetopia, disable?: false)
    :ok
  end

  test "multiple instances can coexist" do
    start_supervised!(TestQueuetopia)
    start_supervised!(TestQueuetopia_2)

    :sys.get_state(TestQueuetopia.Scheduler)
    :sys.get_state(TestQueuetopia_2.Scheduler)
  end

  describe "start_link/1:  poll_interval option" do
    test "preseance to the param" do
      Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 3)

      start_supervised!({TestQueuetopia, poll_interval: 4})

      %{poll_interval: 4} = :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "when there is no param, try to take the value from the config" do
      Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 3)

      start_supervised!(TestQueuetopia)

      %{poll_interval: 3} = :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "when there is no param and no config, takes the default value" do
      start_supervised!(TestQueuetopia)

      %{poll_interval: 60_000} = :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  test "disable? option" do
    Application.put_env(:queuetopia, TestQueuetopia, disable?: true)
    start_supervised!(TestQueuetopia)

    assert is_nil(Process.whereis(TestQueuetopia.Scheduler))
  end

  describe "create_job/5" do
    test "creates the job" do
      jobs_params = Factory.params_for(:job)

      opts = [
        timeout: jobs_params.timeout,
        max_backoff: jobs_params.max_backoff,
        max_attempts: jobs_params.max_attempts
      ]

      assert {:ok, %Job{} = job} =
               TestQueuetopia.create_job(
                 jobs_params.queue,
                 jobs_params.action,
                 jobs_params.params,
                 jobs_params.scheduled_at,
                 opts
               )

      assert job.sequence == 1
      assert job.scope == TestQueuetopia.scope()
      assert job.queue == jobs_params.queue
      assert job.performer == TestQueuetopia.performer()
      assert job.action == jobs_params.action
      assert job.params == jobs_params.params
      assert not is_nil(job.scheduled_at)
      assert job.timeout == jobs_params.timeout
      assert job.max_backoff == jobs_params.max_backoff
      assert job.max_attempts == jobs_params.max_attempts
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
               TestQueuetopia.create_job(queue, action, params, DateTime.utc_now(),
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

    test "a created job is immediatly tried if the queue is empty (no need to wait the poll_interval)" do
      Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 5_000)
      start_supervised!(TestQueuetopia)

      %{queue: queue, action: action, params: params} = Factory.params_for(:success_job)
      assert {:ok, %Job{id: job_id}} = TestQueuetopia.create_job(queue, action, params)

      assert_receive {^queue, ^job_id, :ok}, 1_000

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  describe "list_jobs/1" do
    test "list the jobs order by queue and scheduled_at asc" do
      utc_now = DateTime.utc_now()

      %{id: id_1} =
        Factory.insert(:success_job, queue: "foo", scheduled_at: utc_now |> DateTime.add(2400))

      %{id: id_2} =
        Factory.insert(:success_job, queue: "foo", scheduled_at: utc_now |> DateTime.add(1200))

      %{id: id_3} =
        Factory.insert(:success_job, queue: "bar", scheduled_at: utc_now |> DateTime.add(2400))

      %{id: id_4} =
        Factory.insert(:success_job, queue: "bar", scheduled_at: utc_now |> DateTime.add(1200))

      assert %{data: [%{id: ^id_4}, %{id: ^id_3}, %{id: ^id_2}, %{id: ^id_1}], total: 4} =
               TestQueuetopia.list_jobs()
    end

    test "filters" do
      %{id: id} = job = Factory.insert(:success_job)

      assert %{data: [%{id: ^id}], total: 1} = TestQueuetopia.list_jobs(filters: [id: job.id])

      assert %{data: [%{id: ^id}], total: 1} =
               TestQueuetopia.list_jobs(filters: [scope: job.scope])

      assert %{data: [%{id: ^id}], total: 1} =
               TestQueuetopia.list_jobs(filters: [queue: job.queue])

      assert %{data: [%{id: ^id}], total: 1} =
               TestQueuetopia.list_jobs(filters: [action: job.action])

      assert %{data: [%{id: ^id}], total: 1} =
               TestQueuetopia.list_jobs(filters: [available?: true])

      assert_raise RuntimeError, "Filter not implemented", fn ->
        TestQueuetopia.list_jobs(filters: [params: job.params])
      end

      assert %{data: [], total: 0} = TestQueuetopia.list_jobs(filters: [id: Factory.uuid()])
      assert %{data: [], total: 0} = TestQueuetopia.list_jobs(filters: [scope: "foo"])
      assert %{data: [], total: 0} = TestQueuetopia.list_jobs(filters: [queue: "foo"])
      assert %{data: [], total: 0} = TestQueuetopia.list_jobs(filters: [action: "foo"])
    end

    test "search_query" do
      %{id: id} = job = Factory.insert(:success_job, params: %{foo: "bar"})

      assert %{data: [%{id: ^id}], total: 1} =
               TestQueuetopia.list_jobs(search_query: job.scope |> String.slice(1..10))

      assert %{data: [%{id: ^id}], total: 1} =
               TestQueuetopia.list_jobs(search_query: job.queue |> String.slice(1..10))

      assert %{data: [%{id: ^id}], total: 1} =
               TestQueuetopia.list_jobs(search_query: job.action |> String.slice(1..10))

      assert %{data: [%{id: ^id}], total: 1} = TestQueuetopia.list_jobs(search_query: "ar")

      assert %{data: [%{id: ^id}], total: 1} = TestQueuetopia.list_jobs(search_query: "oo")

      assert %{data: [], total: 0} = TestQueuetopia.list_jobs(search_query: "baz")
    end
  end

  describe "handle_event/1" do
    test "sends a poll message to the scheduler" do
      Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 5_000)
      start_supervised!(TestQueuetopia)

      scheduler_pid = Process.whereis(TestQueuetopia.Scheduler)

      :sys.get_state(TestQueuetopia.Scheduler)

      {:messages, messages} = Process.info(scheduler_pid, :messages)
      assert length(messages) == 0

      :sys.get_state(TestQueuetopia.Scheduler)

      assert :ok = TestQueuetopia.handle_event(:new_incoming_job)
      assert :ok = TestQueuetopia.handle_event(:new_incoming_job)
      assert :ok = TestQueuetopia.handle_event(:new_incoming_job)
      assert :ok = TestQueuetopia.handle_event(:new_incoming_job)
      assert :ok = TestQueuetopia.handle_event(:new_incoming_job)

      {:messages, messages} = Process.info(scheduler_pid, :messages)
      assert length(messages) == 1

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "when the scheduler is down, returns an error tuple" do
      assert {:error, "Queuetopia.TestQueuetopia is down"} ==
               TestQueuetopia.handle_event(:new_incoming_job)
    end
  end
end
