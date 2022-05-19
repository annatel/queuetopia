defmodule Queuetopia.Factories do
  alias Queuetopia.Queue.Job

  def build(:job, attrs) do
    %Job{
      sequence: System.unique_integer([:positive]),
      scope: "scope_#{System.unique_integer([:positive])}",
      queue: "queue_#{System.unique_integer([:positive])}",
      performer: "performer",
      action: "action_#{System.unique_integer([:positive])}",
      params: %{},
      scheduled_at: DateTime.utc_now(),
      timeout: 5_000,
      max_backoff: 0,
      max_attempts: 20
    }
    |> struct!(attrs)
  end
end
