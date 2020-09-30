defmodule Queuetopia.Scheduler do
  @moduledoc """
  The Queuetopia scheduler, polling with a defined interval the next available queues.
  """
  use GenServer

  alias Queuetopia.Locks
  alias Queuetopia.Jobs
  alias Queuetopia.Jobs.Job

  @type option :: {:poll_interval, pos_integer()}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def send_poll(scheduler_pid) when is_pid(scheduler_pid) do
    unless has_poll_messages?(scheduler_pid) do
      Process.send(scheduler_pid, {:poll, continue_polling?: false}, [])
    end
  end

  defp has_poll_messages?(scheduler_pid) do
    {:messages, messages} = Process.info(scheduler_pid, :messages)

    Enum.any?(messages, &match?({:poll, _}, &1))
  end

  @impl true
  @spec init([option()]) :: {:ok, map()}
  def init(opts) do
    Process.send(self(), {:poll, continue_polling?: true}, [])

    state = %{
      repo: Keyword.get(opts, :repo),
      task_supervisor_name: Keyword.get(opts, :task_supervisor_name),
      poll_interval: Keyword.get(opts, :poll_interval),
      repoll_after_job_performed?: Keyword.get(opts, :repoll_after_job_performed?),
      scope: Keyword.get(opts, :scope),
      jobs: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:poll, continue_polling?: continue_polling?}, state) do
    %{
      task_supervisor_name: task_supervisor_name,
      poll_interval: poll_interval,
      repo: repo,
      scope: scope,
      jobs: jobs
    } = state

    jobs = poll_queues(task_supervisor_name, poll_interval, repo, scope, jobs, continue_polling?)
    {:noreply, %{state | jobs: jobs}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{jobs: jobs, repo: repo, scope: scope} = state
      ) do
    job = Map.get(jobs, ref)
    handle_task_result(repo, job, {:error, "down"})

    Locks.unlock_queue(repo, scope, job.queue)

    {:noreply, %{state | jobs: Map.delete(jobs, ref)}}
  end

  def handle_info({:kill, task}, %{jobs: jobs, repo: repo} = state) do
    Task.shutdown(task, :brutal_kill)

    job = Map.get(jobs, task.ref)
    handle_task_result(repo, job, {:error, "timeout"})

    {:noreply, %{state | jobs: Map.delete(jobs, task.ref)}}
  end

  def handle_info({ref, task_result}, %{jobs: jobs, repo: repo, scope: scope} = state) do
    Process.demonitor(ref, [:flush])

    job = Map.get(jobs, ref)

    handle_task_result(repo, job, task_result)

    Locks.unlock_queue(repo, scope, job.queue)

    if state.repoll_after_job_performed?,
      do: Process.send(self(), {:poll, continue_polling?: false}, [])

    {:noreply, %{state | jobs: Map.delete(jobs, ref)}}
  end

  defp handle_task_result(repo, job, result) do
    unless is_nil(job) do
      Jobs.persist_result(repo, job, result)
    end
  end

  defp poll_queues(task_supervisor_name, poll_interval, repo, scope, jobs, continue_polling?) do
    Locks.release_expired_locks(repo, scope)

    jobs =
      Jobs.list_available_pending_queues(repo, scope)
      |> Enum.map(&perform_next_pending_job(&1, task_supervisor_name, repo, scope))
      |> Enum.reject(&is_nil(&1))
      |> Enum.into(%{})
      |> Map.merge(jobs)

    if continue_polling? do
      Process.send_after(self(), {:poll, continue_polling?: true}, poll_interval)
    end

    jobs
  end

  defp perform_next_pending_job(
         queue,
         task_supervisor_name,
         repo,
         scope
       ) do
    with %Job{} <- job = Jobs.get_next_pending_job(repo, scope, queue),
         {:ok, job} <- Jobs.fetch_job(repo, job) do
      task = Task.Supervisor.async_nolink(task_supervisor_name, Jobs, :perform, [job])

      Process.send_after(self(), {:kill, task}, job.timeout)
      {task.ref, job}
    else
      _ -> nil
    end
  end
end
