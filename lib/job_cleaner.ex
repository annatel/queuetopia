defmodule Queuetopia.JobCleaner do
  @moduledoc """
  Removes completed jobs from the queue periodically.

  This GenServer runs in the background and cleans up
  old completed jobs based on the configured interval.
  """

  use GenServer
  alias Queuetopia.Queue

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    cleanup_interval = Keyword.fetch!(opts, :cleanup_interval)
    job_retention = Keyword.get(opts, :job_retention)

    Process.send(self(), :cleanup, cleanup_interval)

    state = %{
      repo: Keyword.fetch!(opts, :repo),
      scope: Keyword.fetch!(opts, :scope),
      cleanup_interval: cleanup_interval,
      job_retention: job_retention
    }

    {:ok, state}
  end

  @impl true
  def handle_info(
        :cleanup,
        %{
          repo: repo,
          scope: scope,
          cleanup_interval: cleanup_interval,
          job_retention: job_retention
        } = state
      ) do

    Queue.cleanup_completed_jobs(repo, scope, job_retention)

    Process.send_after(self(), :cleanup, cleanup_interval)

    {:noreply, state}
  end
end
