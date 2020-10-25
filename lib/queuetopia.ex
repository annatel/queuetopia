defmodule Queuetopia do
  @moduledoc """
  Defines a queues machine.

  A Queuetopia can manage multiple ordered blocking queues.
  All the queues share only the same scheduler and the poll interval.
  They are completely independant from each other.

  A Queuetopia expects a performer to exist.
  For example, the performer can be implemented like this:

      defmodule MyApp.MailQueue.Performer do
        @behaviour Queuetopia.Jobs.Performer

        @impl true
        def perform(%Queuetopia.Jobs.Job{action: "do_x"}) do
          do_x()
        end

        defp do_x(), do: {:ok, "done"}
      end

  And the Queuetopia:

      defmodule MyApp.MailQueue do
        use Queuetopia,
          repo: MyApp.Repo,
          performer: MyApp.MailQueue.Performer
      end
  """

  @doc """
  Creates a job.

  ## Job options
  A job accepts the following options:
    * `:timeout` - The time in milliseconds to wait for the job to
      finish. (default: 60_000)
    * `:max_backoff` - default to 24 * 3600 * 1_000
    * `:max_attempts` - default to 20.

  ## Examples

      iex> MyApp.MailQueue.create_job("mails_queue_1", "send_mail", %{email_address: "toto@mail.com", body: "Welcome"}, [timeout: 1_000, max_backoff: 60_000])

  """
  @callback create_job(binary(), binary(), map(), [Job.option()]) ::
              {:error, Ecto.Changeset.t()} | {:ok, Job.t()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Queuetopia

      use Supervisor

      alias Queuetopia.Jobs.Job

      @typedoc "Option values used by the `start*` functions"
      @type option :: {:poll_interval, non_neg_integer()}

      @repo Keyword.fetch!(opts, :repo)
      @performer Keyword.fetch!(opts, :performer) |> to_string()
      @scope __MODULE__ |> to_string()

      @default_poll_interval 60 * 1_000

      @doc """
      Starts the Queuetopia supervisor process.
      The :poll_interval can also be given in order to config the polling interval of the scheduler.
      """
      @spec start_link([option()]) :: Supervisor.on_start()
      def start_link(opts \\ []) do
        poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
        repoll_after_job_performed? = Keyword.get(opts, :repoll_after_job_performed?, false)

        Supervisor.start_link(
          __MODULE__,
          [
            repo: @repo,
            poll_interval: poll_interval,
            repoll_after_job_performed?: repoll_after_job_performed?
          ],
          name: __MODULE__
        )
      end

      @impl true
      def init(args) do
        children = [
          {Task.Supervisor, name: task_supervisor()},
          {Queuetopia.Scheduler,
           [
             name: scheduler(),
             task_supervisor_name: task_supervisor(),
             repo: Keyword.fetch!(args, :repo),
             repoll_after_job_performed?: Keyword.fetch!(args, :repoll_after_job_performed?),
             scope: @scope,
             poll_interval: Keyword.fetch!(args, :poll_interval)
           ]}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp child_name(child) do
        Module.concat(__MODULE__, child)
      end

      @spec create_job(binary(), binary(), map(), [Job.option()]) ::
              {:error, Ecto.Changeset.t()} | {:ok, Job.t()}
      def create_job(queue, action, params, opts \\ []) do
        result =
          Queuetopia.Jobs.create_job(@repo, @performer, @scope, queue, action, params, opts)

        with {:ok, %Job{}} <- result do
          send_poll()
        end

        result
      end

      def send_poll() do
        scheduler_pid = Process.whereis(scheduler())

        if is_pid(scheduler_pid) do
          Queuetopia.Scheduler.send_poll(scheduler_pid)
          :ok
        else
          {:error, "scheduler down"}
        end
      end

      defp scheduler() do
        child_name("Scheduler")
      end

      defp task_supervisor() do
        child_name("TaskSupervisor")
      end

      def repo() do
        @repo
      end

      def performer() do
        @performer
      end

      def scope() do
        @scope
      end
    end
  end
end
