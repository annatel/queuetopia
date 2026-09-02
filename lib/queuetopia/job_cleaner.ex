defmodule Queuetopia.JobCleaner do
  @moduledoc """
  Removes completed jobs from the queue periodically.

  This GenServer runs in the background and cleans up
  old completed jobs based on the configured interval.
  """

  use GenServer
  alias Queuetopia.Jobs
  alias Queuetopia.PendingQueues

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    dynamic_repo = Keyword.get(opts, :dynamic_repo)

    if dynamic_repo, do: Keyword.fetch!(opts, :repo).put_dynamic_repo(dynamic_repo)

    # Add random dalay to mitigate deadlocks on starts
    job_cleaner_initial_delay =
      opts |> Keyword.fetch!(:job_cleaner_max_initial_delay) |> random_delay()

    Process.send_after(self(), :cleanup, job_cleaner_initial_delay)

    state =
      opts
      |> Keyword.take([:repo, :dynamic_repo, :scope, :cleanup_interval, :job_retention])
      |> Map.new()

    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    %{
      repo: repo,
      scope: scope,
      cleanup_interval: cleanup_interval,
      job_retention: job_retention
    } = state

    Jobs.cleanup_completed_jobs(repo, scope, job_retention)
    PendingQueues.reconcile_pending_queues!(repo, scope)

    Process.send_after(self(), :cleanup, cleanup_interval)
    {:noreply, state}
  end

  defp random_delay(0), do: 0
  defp random_delay(max) when max > 0, do: :rand.uniform(max)
end
