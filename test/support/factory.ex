defmodule Queuetopia.Factory do
  use AntlUtilsEcto.Factory, repo: Queuetopia.TestRepo

  alias Queuetopia.Queue.Job
  alias Queuetopia.Queue.Lock

  @performer Queuetopia.TestPerfomer |> to_string()

  def build(:lock, attrs) do
    locked_at = utc_now()
    locked_until = locked_at |> add(3600, :second)

    %Lock{
      scope: "scope_#{System.unique_integer([:positive])}",
      queue: "queue_#{System.unique_integer([:positive])}",
      locked_at: locked_at,
      locked_by_node: Kernel.inspect(Node.self()),
      locked_until: locked_until
    }
    |> struct!(attrs)
  end

  def build(:expired_lock, attrs) do
    lock = build(:lock, attrs)

    %{lock | locked_until: lock.locked_at}
  end

  def build(:job, attrs) do
    %Job{
      sequence: Queuetopia.Sequences.next_value!(Queuetopia.TestRepo),
      scope: "scope_#{System.unique_integer([:positive])}",
      queue: "queue_#{System.unique_integer([:positive])}",
      performer: @performer,
      action: "action_#{System.unique_integer([:positive])}",
      params: %{"bin_pid" => pid_to_bin()},
      scheduled_at: utc_now(),
      timeout: 5_000,
      max_backoff: 0,
      max_attempts: 20
    }
    |> struct!(attrs)
  end

  def build(:done_job, attrs) do
    job = build(:job, attrs)

    %{job | done_at: utc_now()}
  end

  def build(:raising_job, attrs) do
    job = build(:job, attrs)

    %{job | action: "raise"}
  end

  def build(:slow_job, attrs) do
    attrs = Enum.into(attrs, %{})
    duration = attrs.params["duration"] || 500

    job = build(:job)
    params = job.params |> Map.put("duration", duration)

    job |> Map.merge(attrs) |> Map.merge(%{action: "sleep", params: params})
  end

  def build(:success_job, attrs) do
    job = build(:job, attrs)

    %{job | action: "success"}
  end

  def build(:failure_job, attrs) do
    job = build(:job, attrs)

    %{job | action: "fail"}
  end

  def pid_to_bin(pid \\ self()) do
    pid
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  def bin_to_pid(bin) do
    bin
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end
end
