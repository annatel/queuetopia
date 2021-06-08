defmodule Queuetopia.TestPerfomerWithBackoff do
  use Queuetopia.Performer

  alias Queuetopia.Queue.Job

  @impl true

  def perform(%Job{} = job) do
    Queuetopia.TestPerfomer.perform(job)
  end

  def backoff(%Job{}), do: 20 * 1_000
end
