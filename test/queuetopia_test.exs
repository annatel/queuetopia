defmodule QueuetopiaTest do
  use Queuetopia.DataCase
  alias Queuetopia.{TestQueuetopia, TestQueuetopia_2, TestQueuetopia_RedefTest}
  alias Queuetopia.TestQueuetopia_Convention
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

  describe "start_link/1: dedicated scheduler pool" do
    setup do
      on_exit(fn -> System.delete_env("QUEUETOPIA_SCHEDULER_POOL_SIZE") end)
      :ok
    end

    test "by default, the scheduler and the job cleaner poll through the repo" do
      start_supervised!(
        {TestQueuetopia, cleanup_interval: {1, :hour}, job_cleaner_max_initial_delay: 0}
      )

      assert %{repo: TestRepo, dynamic_repo: nil} = :sys.get_state(TestQueuetopia.Scheduler)
      assert %{repo: TestRepo, dynamic_repo: nil} = :sys.get_state(TestQueuetopia.JobCleaner)
    end

    test "when enabled without QUEUETOPIA_SCHEDULER_POOL_SIZE, raises at startup" do
      Application.put_env(:queuetopia, TestQueuetopia, dedicated_scheduler_pool?: true)

      assert_raise System.EnvError, fn -> TestQueuetopia.start_link() end
    end

    test "when enabled, the scheduler and the job cleaner poll through a shared dedicated pool" do
      System.put_env("QUEUETOPIA_SCHEDULER_POOL_SIZE", "2")
      Application.put_env(:queuetopia, TestQueuetopia, dedicated_scheduler_pool?: true)

      pool = Queuetopia.SchedulerPool.name(TestRepo)
      start_pool_in_auto_sandbox(pool)

      start_supervised!(
        {TestQueuetopia, cleanup_interval: {1, :hour}, job_cleaner_max_initial_delay: 0}
      )

      assert is_pid(Process.whereis(pool))
      assert %{repo: TestRepo, dynamic_repo: ^pool} = :sys.get_state(TestQueuetopia.Scheduler)
      assert %{repo: TestRepo, dynamic_repo: ^pool} = :sys.get_state(TestQueuetopia.JobCleaner)
    end
  end

  test "disable? option" do
    Application.put_env(:queuetopia, TestQueuetopia, disable?: true)
    start_supervised!(TestQueuetopia)

    assert is_nil(Process.whereis(TestQueuetopia.Scheduler))
  end

  describe "create_job/5" do
    test "creates the job" do
      jobs_params = params_for(:job)

      opts = [
        timeout: jobs_params.timeout,
        max_backoff: jobs_params.max_backoff,
        max_attempts: jobs_params.max_attempts
      ]

      %{rows: [[sequence]], num_rows: 1} =
        Ecto.Adapters.SQL.query!(Queuetopia.TestRepo, "SELECT sequence FROM queuetopia_sequences")

      assert {:ok, %Job{} = job} =
               TestQueuetopia.create_job(
                 jobs_params.queue,
                 jobs_params.action,
                 jobs_params.params,
                 jobs_params.scheduled_at,
                 opts
               )

      assert job.sequence == sequence + 1
      assert job.scope == TestQueuetopia.scope()
      assert job.queue == jobs_params.queue
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
      } = params_for(:job)

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

      %{queue: queue, action: action, params: params} = params_for(:job)

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

      %{queue: queue, action: action, params: params} = params_for(:success_job)
      assert {:ok, %Job{id: job_id}} = TestQueuetopia.create_job(queue, action, params)

      assert_receive {^queue, ^job_id, :ok}, 1_000

      :sys.get_state(TestQueuetopia.Scheduler)
    end

    test "with notify?: false, does not wake up the scheduler" do
      Application.put_env(:queuetopia, TestQueuetopia, poll_interval: 5_000)
      start_supervised!(TestQueuetopia)

      :sys.get_state(TestQueuetopia.Scheduler)

      %{queue: queue, action: action, params: params} = params_for(:success_job)

      assert {:ok, %Job{id: job_id}} =
               TestQueuetopia.create_job(queue, action, params, DateTime.utc_now(),
                 notify?: false
               )

      refute_receive {^queue, ^job_id, :ok}, 500

      assert :ok = TestQueuetopia.handle_event(:new_incoming_job)
      assert_receive {^queue, ^job_id, :ok}, 1_000

      :sys.get_state(TestQueuetopia.Scheduler)
    end
  end

  test "performs the jobs with the performer module named after the scope" do
    start_supervised!({TestQueuetopia_Convention, poll_interval: 5_000})

    %{queue: queue, action: action, params: params} = params_for(:success_job)

    assert {:ok, %Job{id: job_id}} = TestQueuetopia_Convention.create_job(queue, action, params)

    assert_receive {^queue, ^job_id, :performed_by_convention}, 1_000
  end

  test "create_job!/5 raises when params are not valid" do
    assert_raise Ecto.InvalidChangesetError, fn ->
      TestQueuetopia.create_job!("queue", "action", %{}, DateTime.utc_now(), timeout: -1)
    end
  end

  test "list_jobs/1" do
    %{id: id} = insert!(:job)

    assert [%{id: ^id}] = TestQueuetopia.list_jobs()
  end

  test "paginate_jobs/1" do
    %{id: id_1} = insert!(:job, sequence: 1)
    %{id: id_2} = insert!(:job, sequence: 2)

    assert %{data: [%{id: ^id_2}], total: 2} = TestQueuetopia.paginate_jobs(1, 1)
    assert %{data: [%{id: ^id_1}], total: 2} = TestQueuetopia.paginate_jobs(1, 2)
    assert %{data: [], total: 2} = TestQueuetopia.paginate_jobs(1, 3)
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

  defp start_pool_in_auto_sandbox(pool) do
    {:ok, _pid} = TestRepo.start_link(name: pool, pool_size: 2)
    TestRepo.put_dynamic_repo(pool)
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :auto)
    TestRepo.put_dynamic_repo(TestRepo)
  end

  describe "next_value!/0" do
    test "by default use internal function based on db sequence" do
      TestRepo.update_all("queuetopia_sequences", set: [sequence: 41])

      assert 42 = TestQueuetopia.next_value!()
    end

    test "can be redefined" do
      assert 666 = TestQueuetopia_RedefTest.next_value!()
    end
  end
end
