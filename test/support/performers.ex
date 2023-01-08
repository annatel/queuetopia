defmodule Queuetopia.TestPerfomer do
  use Queuetopia.Performer
  import Queuetopia.Factory
  alias Queuetopia.Queue.Job

  @performer Queuetopia.TestPerfomer |> to_string()

  @impl true

  def perform(
        %Job{
          performer: @performer,
          queue: queue,
          action: action,
          params: %{"bin_pid" => bin_pid},
          id: job_id
        } = job
      ) do
    pid = bin_to_pid(bin_pid)

    case action do
      "success" ->
        send(pid, {queue, job_id, :ok})

        :ok

      "sleep" ->
        send(pid, {queue, job_id, :started})
        %{"duration" => duration} = job.params

        Process.send_after(pid, {queue, job_id, :timeout}, job.timeout)

        :ok = Process.sleep(duration)

        send(pid, {queue, job_id, :ok})

        :ok

      "fail" ->
        send(pid, {queue, job_id, :fail})

        {:error, "error"}

      "raise" ->
        send(pid, {queue, job_id, :raise})

        raise RuntimeError, "down"
    end
  end
end

defmodule Queuetopia.TestPerfomerWithBackoff do
  use Queuetopia.Performer

  alias Queuetopia.Queue.Job

  @impl true

  def perform(%Job{} = job) do
    Queuetopia.TestPerfomer.perform(job)
  end

  @impl true
  def backoff(%Job{}), do: 20 * 1_000
end

defmodule Queuetopia.TestPerfomerWithHandleFailedJob do
  use Queuetopia.Performer

  alias Queuetopia.Queue.Job

  @impl true
  def perform(%Job{} = job) do
    Queuetopia.TestPerfomer.perform(job)
  end

  @impl true
  def handle_failed_job!(%Job{} = job) do
    send(self(), {:job, job})
    :ok
  end
end
