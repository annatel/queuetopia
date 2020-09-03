defmodule Queuetopia.TestPerfomer do
  @behaviour Queuetopia.Jobs.Performer

  alias Queuetopia.Jobs.Job
  alias Queuetopia.Factory

  @performer Queuetopia.TestPerfomer |> to_string()

  @impl true

  def perform(%Job{performer: @performer, action: action, params: %{"bin_pid" => bin_pid}} = job) do
    pid = Factory.bin_to_pid(bin_pid)

    case action do
      "success" ->
        send(pid, :ok)

        :ok

      "sleep" ->
        send(pid, :started)
        %{"duration" => duration} = job.params

        Process.send_after(pid, :timeout, job.timeout)

        :ok = Process.sleep(duration)

        send(pid, :ok)

        :ok

      "fail" ->
        send(pid, :fail)

        {:error, "error"}

      "raise" ->
        send(pid, :raise)

        raise RuntimeError, "down"
    end
  end
end
