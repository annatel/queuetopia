defmodule Queuetopia.Scheduler do
  @moduledoc """
  The Queuetopia scheduler, polling with a defined interval the next available queues.
  """
  use GenServer

  alias Queuetopia.Queue
  alias Queuetopia.Queue.Job

  @type option :: {:poll_interval, pos_integer()}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def send_poll(scheduler_pid) when is_pid(scheduler_pid) do
    unless has_poll_messages?(scheduler_pid) do
      Process.send(scheduler_pid, {:poll, one_time?: true}, [])
    end
  end

  defp has_poll_messages?(scheduler_pid) do
    {:messages, messages} = Process.info(scheduler_pid, :messages)

    Enum.any?(messages, &match?({:poll, _}, &1))
  end

  @impl true
  @spec init([option()]) :: {:ok, map()}
  def init(opts) do
    Process.send(self(), {:poll, one_time?: false}, [])

    state = %{
      repo: Keyword.get(opts, :repo),
      task_supervisor_name: Keyword.get(opts, :task_supervisor_name),
      poll_interval: Keyword.get(opts, :poll_interval),
      scope: Keyword.get(opts, :scope),
      jobs: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:poll, one_time?: one_time?}, state) do
    %{
      task_supervisor_name: task_supervisor_name,
      poll_interval: poll_interval,
      repo: repo,
      scope: scope,
      jobs: jobs
    } = state

    jobs = poll_queues(task_supervisor_name, poll_interval, repo, scope, jobs, one_time?)
    {:noreply, %{state | jobs: jobs}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{jobs: jobs, repo: repo, scope: scope} = state
      ) do
    job = Map.get(jobs, ref)
    :ok = handle_task_result(repo, job, {:error, "down"})

    Queue.unlock_queue(repo, scope, job.queue)
    {:noreply, %{state | jobs: Map.delete(jobs, ref)}}
  end

  def handle_info({:kill, task}, %{jobs: jobs, repo: repo} = state) do
    Task.shutdown(task, :brutal_kill)

    job = Map.get(jobs, task.ref)
    :ok = handle_task_result(repo, job, {:error, "timeout"})

    {:noreply, %{state | jobs: Map.delete(jobs, task.ref)}}
  end

  def handle_info({ref, task_result}, %{jobs: jobs, repo: repo, scope: scope} = state) do
    Process.demonitor(ref, [:flush])

    job = Map.get(jobs, ref)

    :ok = handle_task_result(repo, job, task_result)

    Queue.unlock_queue(repo, scope, job.queue)

    Process.send(self(), {:poll, one_time?: true}, [])
    {:messages, messages} = Process.info(self, :messages)
    IO.inspect(messages)

    {:noreply, %{state | jobs: Map.delete(jobs, ref)}}
  end

  defp handle_task_result(repo, job, result) do
    unless is_nil(job) do
      Queue.persist_result(repo, job, result)
    end

    :ok
  end

  defp poll_queues(task_supervisor_name, poll_interval, repo, scope, jobs, one_time?) do
    Queue.release_expired_locks(repo, scope)

    jobs =
      Queue.list_available_pending_queues(repo, scope)
      |> Enum.map(&perform_next_pending_job(&1, task_supervisor_name, repo, scope))
      |> Enum.reject(&is_nil(&1))
      |> Enum.into(%{})
      |> Map.merge(jobs)

    unless one_time? do
      Process.send_after(self(), {:poll, one_time?: false}, poll_interval)
      {:messages, messages} = Process.info(self, :messages)
      IO.inspect(messages)
    end

    jobs
  end

  defp perform_next_pending_job(
         queue,
         task_supervisor_name,
         repo,
         scope
       ) do
    with %Job{} <- job = Queue.get_next_pending_job(repo, scope, queue),
         {:ok, job} <- Queue.fetch_job(repo, job) do
      task = Task.Supervisor.async_nolink(task_supervisor_name, Queue, :perform, [job])

      Process.send_after(self(), {:kill, task}, job.timeout)
      {task.ref, job}
    else
      _ -> nil
    end
  end
end
