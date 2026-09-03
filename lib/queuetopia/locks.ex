defmodule Queuetopia.Locks do
  @moduledoc false

  alias Queuetopia.Locks.Lock
  alias Queuetopia.Locks.LockQueryable

  @lock_security_retention 1_000

  @doc false
  @spec lock_queue(module, binary, binary, integer) :: {:error, :locked} | {:ok, Lock.t()}
  def lock_queue(repo, scope, queue, timeout)
      when is_binary(queue) and is_integer(timeout) do
    utc_now = DateTime.utc_now()
    lock_retention = timeout + @lock_security_retention

    %Lock{}
    |> Lock.changeset(%{
      scope: scope,
      queue: queue,
      locked_at: utc_now,
      locked_by_node: Kernel.inspect(Node.self()),
      locked_until: DateTime.add(utc_now, lock_retention, :millisecond)
    })
    |> repo.insert()
    |> case do
      {:ok, %Lock{} = lock} -> {:ok, lock}
      {:error, _changeset} -> {:error, :locked}
    end
  end

  @doc false
  @spec release_expired_locks(module, binary) :: any()
  def release_expired_locks(repo, scope) do
    LockQueryable.queryable()
    |> LockQueryable.filter(scope: scope, expired?: true)
    |> repo.delete_all()
  end

  @doc false
  @spec unlock_queue(module, binary, binary) :: any
  def unlock_queue(repo, scope, queue) do
    LockQueryable.queryable()
    |> LockQueryable.filter(scope: scope, queue: queue)
    |> repo.delete_all()
  end
end
