defmodule Queuetopia do
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> List.first()

  @doc """
  Defines a queues machine.

  A Queuetopia can manage multiple ordered blocking queues.
  All the queues share only the same scheduler and the same poll interval.
  They are completely independants.

  A Queuetopia expects a performer to exist.
  For example, the performer can be implemented like this:

      defmodule MyApp.MailQueuetopia.Performer do
        @behaviour Queuetopia.Performer

        @impl true
        def perform(%Queuetopia.Queue.Job{action: "do_x"}) do
          do_x()
        end

        defp do_x(), do: {:ok, "done"}
      end

  And the Queuetopia:

      defmodule MyApp.MailQueuetopia do
        use Queuetopia,
          otp_app: :my_app,
          performer: MyApp.MailQueuetopia.Performer,
          repo: MyApp.Repo
      end

      # config/config.exs
      config :my_app, MyApp.MailQueuetopia,
        poll_interval: 60 * 1_000,
        disable?: true

  """

  @callback next_value!() :: integer

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Queuetopia

      use Supervisor
      alias Queuetopia.Queue.Job

      @type option :: {:poll_interval, non_neg_integer()}

      @otp_app Keyword.fetch!(opts, :otp_app)
      @repo Keyword.fetch!(opts, :repo)
      @performer Keyword.fetch!(opts, :performer) |> to_string()
      @scope __MODULE__ |> to_string()

      @default_poll_interval 60 * 1_000

      defp config(otp_app, queue) when is_atom(otp_app) and is_atom(queue) do
        config = Application.get_env(otp_app, queue, [])
        [otp_app: otp_app] ++ config
      end

      @doc """
      Starts the Queuetopia supervisor process.
      The :poll_interval can also be given in order to config the polling interval of the scheduler.
      """
      @spec start_link([option]) :: Supervisor.on_start()
      def start_link(opts \\ []) do
        config = config(@otp_app, __MODULE__)

        poll_interval =
          Keyword.get(opts, :poll_interval) ||
            Keyword.get(config, :poll_interval) ||
            @default_poll_interval

        disable? = Keyword.get(config, :disable?, false)

        opts = [
          repo: @repo,
          poll_interval: poll_interval,
          number_of_concurrent_jobs: Keyword.get(config, :number_of_concurrent_jobs)
        ]

        if disable?, do: :ignore, else: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
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
             scope: @scope,
             poll_interval: Keyword.fetch!(args, :poll_interval),
             number_of_concurrent_jobs: Keyword.fetch!(args, :number_of_concurrent_jobs)
           ]}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp child_name(child) do
        Module.concat(__MODULE__, child)
      end

      @doc """
      Creates a job.

      ## Job options
      A job accepts the following options:

        * `:timeout` - The time in milliseconds to wait for the job to
          finish. (default: 60_000)

        * `:max_backoff` - default to 24 * 3600 * 1_000

        * `:max_attempts` - default to 20.

      It is possible to schedule jobs in the future. In this FIFO, the first_in is determined by the scheduled_at.
      Jobs having the same scheduled_at will be ordered by their sequence (arrival order).

      ## Examples

          iex> MyApp.MailQueuetopia.create_job(
              "mails_queue_1",
              "send_mail",
              %{email_address: "toto@mail.com", body: "Welcome"},
              DateTime.utc_now(),
              [timeout: 1_000, max_backoff: 60_000]
            )
          {:ok, %Job{}}
      """
      @spec create_job(binary, binary, map, DateTime.t(), [Job.option()] | []) ::
              {:error, Ecto.Changeset.t()} | {:ok, Job.t()}
      def create_job(queue, action, params, scheduled_at \\ DateTime.utc_now(), opts \\ [])
          when is_binary(queue) and is_binary(action) and is_map(params) do
        attrs =
          %{
            scope: @scope,
            queue: queue,
            performer: @performer,
            sequence: next_value!(),
            action: action,
            params: params,
            scheduled_at: scheduled_at
          }
          |> Map.merge(Enum.into(opts, %{}))

        with result = {:ok, _} <- Queuetopia.Queue.create_job(attrs, @repo) do
          handle_event(:new_incoming_job)
          result
        else
          error -> error
        end
      end

      @doc """
      Similar to `c:create_job/5` but raises if the changeset is not valid.

      Raises if more than one entry.


      ## Examples

          iex> MyApp.MailQueuetopia.create_job!(
              "mails_queue_1",
              "send_mail",
              %{email_address: "toto@mail.com", body: "Welcome"},
              DateTime.utc_now(),
              [timeout: 1_000, max_backoff: 60_000]
            )
          %Job{}
      """
      @spec create_job!(binary, binary, map, DateTime.t(), [Job.option()] | []) ::
              Job.t()
      def create_job!(queue, action, params, scheduled_at \\ DateTime.utc_now(), opts \\ [])
          when is_binary(queue) and is_binary(action) and is_map(params) do
        create_job(queue, action, params, scheduled_at, opts)
        |> case do
          {:ok, %Job{} = job} ->
            job

          {:error, %Ecto.Changeset{} = changeset} ->
            raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
        end
      end

      @spec list_jobs(Queue.list_options()) :: [Job.t()]
      def list_jobs(opts \\ []) do
        Queuetopia.Queue.list_jobs(@repo, opts)
      end

      @spec paginate_jobs(pos_integer, pos_integer, Queue.list_options()) :: %{
              data: [Job.t()],
              total: any,
              page_size: pos_integer,
              page_number: pos_integer
            }
      def paginate_jobs(page_size, page_number, opts \\ [])
          when is_integer(page_number) and is_integer(page_size) and is_list(opts) do
        Queuetopia.Queue.paginate_jobs(@repo, page_size, page_number, opts)
      end

      @spec abort_job(Job.t()) :: :ok | {:error, any}
      def abort_job(%Job{} = job) do
        scheduler_pid = Process.whereis(scheduler())

        if is_pid(scheduler_pid) do
          Queuetopia.Scheduler.abort_job(scheduler_pid, job)
        else
          {:error, "#{inspect(__MODULE__)} is down"}
        end
      end

      def handle_event(:new_incoming_job) do
        listen(:new_incoming_job)
      end

      @since "1.5.0"
      @deprecated "Use handle_event/1 instead"
      def listen(:new_incoming_job) do
        scheduler_pid = Process.whereis(scheduler())

        if is_pid(scheduler_pid) do
          Queuetopia.Scheduler.send_poll(scheduler_pid)
          :ok
        else
          {:error, "#{inspect(__MODULE__)} is down"}
        end
      end

      def repo(), do: @repo
      def performer(), do: @performer
      def scope(), do: @scope

      @impl Queuetopia
      def next_value!() do
        repo() |> Queuetopia.Sequences.next_value!()
      end

      defoverridable next_value!: 0

      defp scheduler(), do: child_name("Scheduler")
      defp task_supervisor(), do: child_name("TaskSupervisor")
    end
  end
end
