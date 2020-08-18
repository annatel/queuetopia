defmodule Queuetopia.Sequences do
  @moduledoc false

  def next(:queuetopia_sequences, repo) do
    Ecto.Adapters.SQL.query!(
      repo,
      "UPDATE `queuetopia_sequences` SET sequence = LAST_INSERT_ID(sequence+1)"
    )

    %{rows: [[last_insert_id]]} = repo.query!("SELECT LAST_INSERT_ID()")

    last_insert_id
  end
end
