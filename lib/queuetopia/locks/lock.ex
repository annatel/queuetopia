defmodule Queuetopia.Locks.Lock do
  use Ecto.Schema
  import Ecto.Changeset, only: [cast: 3, unique_constraint: 3, validate_required: 2]

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "queuetopia_locks" do
    field(:scope, :string)
    field(:queue, :string)
    field(:locked_at, :utc_datetime)
    field(:locked_by_node, :string)
    field(:locked_until, :utc_datetime)

    timestamps()
  end

  @spec changeset(Lock.t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = lock, attrs) when is_map(attrs) do
    lock
    |> cast(attrs, [:scope, :queue, :locked_at, :locked_by_node, :locked_until])
    |> validate_required([:scope, :queue, :locked_at, :locked_by_node, :locked_until])
    |> unique_constraint(:queue, name: :queuetopia_locks_scope_queue_index)
  end
end
