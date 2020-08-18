defmodule Queuetopia.Jobs.Performer do
  @moduledoc """
  The behaviour for a Queuetopia performer.
  """
  alias Queuetopia.Jobs.Job

  @doc """
  Callback invoked by the Queuetopia to perfom a job.
  It may return :ok, an :ok tuple or a tuple error, with a string as error.
  Note that any failure in the processing will cause the job to be retried.
  """
  @callback perform(Job.t()) :: :ok | {:ok, any()} | {:error, binary()}
end
