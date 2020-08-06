defmodule Queuetopia.Sequences.Sequence do
  use Ecto.Schema
  import Ecto.Changeset

  schema "queuetopia_sequences" do
    field(:sequence, :integer)

    timestamps()
  end

  def changeset(%__MODULE__{} = sequence, attrs) when is_map(attrs) do
    sequence
    |> cast(attrs, [:sequence])
  end
end
