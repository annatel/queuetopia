defmodule Queuetopia.InMemorySequence do
  use Agent

  def start_link(opts) do
    Agent.start_link(fn -> next_sequence(opts[:repo]) end, name: opts[:name])
  end

  def next_value!(process) do
    Agent.get_and_update(process, &{&1, &1 + 1})
  end

  defp next_sequence(repo) do
    %{rows: [[max_seq]]} = repo.query!("SELECT max(sequence) FROM queuetopia_jobs")
    (max_seq || 0) + 1
  end
end
