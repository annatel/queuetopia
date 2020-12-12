defmodule Queuetopia.Test.Assertions do
  import ExUnit.Assertions
  require Ecto.Query
  alias Queuetopia.Jobs.Job

  @doc """
  Asserts the job has juste been created
  """

  def assert_job_created(queuetopia) when is_atom(queuetopia) do
    repo = queuetopia.repo()

    job = Job |> Ecto.Query.last() |> repo.one()
    refute is_nil(job)
    job
  end

  def assert_job_created(queuetopia, queue) when is_atom(queuetopia) and is_binary(queue) do
    repo = queuetopia.repo()

    job =
      Job
      |> Ecto.Query.where([job], job.queue == ^queue)
      |> Ecto.Query.last()
      |> repo.one()

    refute is_nil(job)
    job
  end

  def assert_job_created(queuetopia, %{} = params) when is_atom(queuetopia) do
    job = assert_job_created(queuetopia)
    assert ^params = job
  end

  def assert_job_created(queuetopia, queue, %{} = params)
      when is_atom(queuetopia) and is_binary(queue) do
    job = assert_job_created(queuetopia, queue)
    assert ^params = job
  end
end
