defmodule Queuetopia.Factory do
  use ExMachina.Ecto, repo: Queuetopia.TestRepo

  alias Queuetopia.Jobs.Job
  alias Queuetopia.Locks.Lock

  @job_performer Queuetopia.TestPerfomer

  @spec uuid :: <<_::288>>
  def uuid() do
    Ecto.UUID.generate()
  end

  @spec utc_datetime :: DateTime.t()
  def utc_datetime() do
    DateTime.from_naive!(~N[2018-12-19T00:00:00Z], "Etc/UTC")
  end

  @spec lock_factory :: Queuetopia.Locks.Lock.t()
  def lock_factory do
    locked_at = DateTime.utc_now() |> DateTime.truncate(:second)
    locked_until = locked_at |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    %Lock{
      scope: sequence("scope_"),
      queue: sequence("queue_"),
      locked_at: locked_at,
      locked_by_node: Kernel.inspect(Node.self()),
      locked_until: locked_until
    }
  end

  def expired_lock_factory() do
    lock = build(:lock)

    %{lock | locked_until: lock.locked_at}
  end

  @spec job_factory() :: Job.t()
  def job_factory() do
    %Job{
      sequence: String.pad_leading(sequence("0"), 4, ["0"]),
      scope: sequence("scope_"),
      queue: sequence("queue_"),
      performer: @job_performer |> to_string(),
      action: sequence("action_"),
      params: %{"bin_pid" => pid_to_bin()},
      scheduled_at: DateTime.utc_now(),
      timeout: 5_000,
      max_backoff: 0,
      max_attempts: 20
    }
  end

  def done_job_factory() do
    job = build(:job)
    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{job | done_at: utc_now}
  end

  def raising_job_factory(attrs) do
    job = build(:job)

    merge_attributes(job, Map.merge(attrs, %{action: "raise"}))
  end

  def slow_job_factory(attrs) do
    duration = attrs.params["duration"] || 500

    job = build(:job)
    params = job.params |> Map.put("duration", duration)

    merge_attributes(job, Map.merge(attrs, %{action: "sleep", params: params}))
  end

  def success_job_factory(attrs) do
    job = build(:job)

    merge_attributes(job, Map.merge(attrs, %{action: "success"}))
  end

  def failure_job_factory(attrs) do
    job = build(:job)

    merge_attributes(job, Map.merge(attrs, %{action: "fail"}))
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
