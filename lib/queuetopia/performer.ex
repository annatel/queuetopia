defmodule Queuetopia.Performer do
  @moduledoc """
  The behaviour for a Queuetopia performer.
  """
  alias Queuetopia.Queue.Job

  @doc """
  Callback invoked by the Queuetopia to perfom a job.
  It may return :ok, an :ok tuple or a tuple error, with a string as error.
  Note that any failure in the processing will cause the job to be retried.
  """
  @callback perform(Job.t()) :: :ok | {:ok, any()} | {:error, binary}
  @callback backoff(job :: Job.t()) :: pos_integer()

  defmacro __using__(_) do
    quote do
      @behaviour Queuetopia.Performer

      alias Queuetopia.Queue.Job
      alias AntlUtilsElixir.Math

      @impl Queuetopia.Performer
      def backoff(%Job{} = job) do
        exponential_backoff(job.attempts, job.max_backoff)
      end

      defp exponential_backoff(iteration, max_backoff) do
        backoff = ((Math.pow(2, iteration) |> round) + 1) * 1_000
        min(backoff, max_backoff)
      end

      defoverridable backoff: 1
    end
  end
end
