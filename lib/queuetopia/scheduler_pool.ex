defmodule Queuetopia.SchedulerPool do
  @moduledoc """
  A dedicated connection pool for the scheduling queries.

  Enabled per Queuetopia with `dedicated_scheduler_pool?: true` in the
  Queuetopia config. The pool is a second instance of the Queuetopia's repo —
  same config, same adapter — shared by every Queuetopia of the same repo,
  and sized by the QUEUETOPIA_SCHEDULER_POOL_SIZE environment variable
  (required when the pool is enabled).
  """

  @spec name(module) :: atom
  def name(repo), do: Module.concat(repo, "Scheduler")

  @spec pool_size() :: pos_integer
  def pool_size() do
    "QUEUETOPIA_SCHEDULER_POOL_SIZE" |> System.fetch_env!() |> String.to_integer()
  end

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :repo)},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    {repo, opts} = Keyword.pop!(opts, :repo)

    case repo.start_link([name: name(repo)] ++ opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> :ignore
      error -> error
    end
  end
end
