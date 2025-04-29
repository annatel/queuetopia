defmodule Queuetopia.Migrations do
  use Ecto.Migration

  @initial_version 0
  @current_version 6
  def up(opts \\ []) when is_list(opts) do
    from_version = Keyword.get(opts, :from_version, @initial_version) |> Kernel.+(1)
    to_version = Keyword.get(opts, :to_version, @current_version)

    if from_version <= to_version do
      change(from_version..to_version, :up)
    end
  end

  def down(opts \\ []) when is_list(opts) do
    from_version = Keyword.get(opts, :from_version, @current_version)
    to_version = Keyword.get(opts, :to_version, @initial_version) |> Kernel.+(1)

    if from_version >= to_version do
      change(from_version..to_version, :down)
    end
  end

  @doc false
  def initial_version, do: @initial_version

  @doc false
  def current_version, do: @current_version

  defp change(range, direction) do
    for index <- range do
      [__MODULE__, "V#{index}"]
      |> Module.concat()
      |> apply(direction, [])
    end
  end
end
