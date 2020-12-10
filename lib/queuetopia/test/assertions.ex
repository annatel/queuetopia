defmodule Queuetopia.Test.Assertions do
  import ExUnit.Assertions
  alias Queuetopia.Jobs.Job

  @doc """
  Asserts the job has juste been created
  """

  def assert_job_created(queue, %{} = params) do
    repo = queue.repo()

    job =
      Job
      |> Ecto.Query.last()
      |> repo.one()

    refute is_nil(job) && assert(^params = job)
  end
end
