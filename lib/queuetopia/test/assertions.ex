defmodule Queuetopia.Test.Assertions do
  import ExUnit.Assertions
  require Ecto.Query
  alias Queuetopia.Jobs.Job

  @doc """
  Asserts the job has juste been created

  It can be used as below:

    job = MyQueuetopia.Jobs.create_job("mailer_queue", "deliver_mail", %{body: "hello", from: "from", to: "to"})

    assert_job_created(MyQueuetopia)
    assert_job_created(MyQueuetopia, "mailer_queue")
    assert_job_created(MyQueuetopia, "mailer_queue", %{params: %{body: "hello"}})
    assert_job_created(MyQueuetopia, "mailer_queue", %{action: "deliver_email", params: %{body: "hello"}})

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

  def assert_job_created(queuetopia, %Job{} = job) when is_atom(queuetopia) do
    assert_job_created(queuetopia, Map.from_struct(job) |> Map.delete(:__meta__))
  end

  def assert_job_created(queuetopia, %{} = attrs) when is_atom(queuetopia) do
    job = assert_job_created(queuetopia)
    job |> Map.from_struct() |> assert_job_attrs_match(attrs)
  end

  def assert_job_created(queuetopia, queue, %Job{} = job)
      when is_atom(queuetopia) and is_binary(queue) do
    assert_job_created(queuetopia, queue, Map.from_struct(job) |> Map.delete(:__meta__))
  end

  def assert_job_created(queuetopia, queue, %{} = attrs)
      when is_atom(queuetopia) and is_binary(queue) do
    job = assert_job_created(queuetopia, queue)
    job |> Map.from_struct() |> assert_job_attrs_match(attrs)
  end

  defp assert_job_attrs_match(job_attrs, %{params: %{} = params} = attrs) do
    assert MapSet.subset?(
             params |> MapSet.new(),
             job_attrs.params |> Recase.Enumerable.atomize_keys() |> MapSet.new()
           ),
           """
           Expected: #{inspect(job_attrs |> Recase.Enumerable.atomize_keys())}
           Got:  #{inspect(attrs)}
           """

    assert_job_attrs_match(job_attrs, attrs |> Map.delete(:params))
  end

  defp assert_job_attrs_match(job_attrs, %{} = attrs) do
    assert MapSet.subset?(attrs |> MapSet.new(), job_attrs |> MapSet.new()), """
      Expected: #{inspect(job_attrs |> Recase.Enumerable.atomize_keys())}
      Got:  #{inspect(attrs)}
    """
  end
end
