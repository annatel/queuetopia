defmodule Queuetopia.TestPerfomer do
  use Queuetopia.Performer

  alias Queuetopia.Queue.Job
  alias Queuetopia.Factory

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
    pid = Factory.bin_to_pid(bin_pid)

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
