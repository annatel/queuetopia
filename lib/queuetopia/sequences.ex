defmodule Queuetopia.Sequences do
  @moduledoc false

  def next_value!(:queuetopia_sequences, repo) do
    %{rows: [[next_value]]} = repo.query!("SELECT queuetopia_nextval_gapless_sequence()")

    next_value
  end
end
