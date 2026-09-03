defmodule Queuetopia.Factories do
  alias Queuetopia.Jobs.Job
  alias Queuetopia.PendingQueues.PendingQueue

  def build(:job, attrs) do
    %Job{
      sequence: System.unique_integer([:positive]),
      scope: "scope_#{System.unique_integer([:positive])}",
      queue: "queue_#{System.unique_integer([:positive])}",
      action: "action_#{System.unique_integer([:positive])}",
      params: %{},
      scheduled_at: DateTime.utc_now(),
      timeout: 5_000,
      max_backoff: 0,
      max_attempts: 20
    }
    |> struct!(attrs)
  end

  def build(:pending_queue, attrs) do
    %PendingQueue{
      scope: "scope_#{System.unique_integer([:positive])}",
      queue: "queue_#{System.unique_integer([:positive])}",
      next_performable_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
    |> struct!(attrs)
  end
end
