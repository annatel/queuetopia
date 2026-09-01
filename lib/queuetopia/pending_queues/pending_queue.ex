defmodule Queuetopia.PendingQueues.PendingQueue do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset, only: [cast: 3, validate_required: 2, unique_constraint: 3]

  @type t :: %__MODULE__{}

  @primary_key false
  schema "queuetopia_pending_queues" do
    field(:scope, :string, primary_key: true)
    field(:queue, :string, primary_key: true)
    field(:next_runnable_at, :utc_datetime)

    timestamps()
  end

  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = pending_queue, attrs) when is_map(attrs) do
    pending_queue
    |> cast(attrs, [:scope, :queue, :next_runnable_at])
    |> validate_required([:scope, :queue, :next_runnable_at])
    |> unique_constraint(:scope, name: :PRIMARY)
    |> unique_constraint(:scope, name: :queuetopia_pending_queues_pkey)
  end
end
