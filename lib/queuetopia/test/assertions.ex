defmodule Queuetopia.Test.Assertions do
  import ExUnit.Assertions
  require Ecto.Query
  alias Queuetopia.Queue.Job

  @doc """
  Asserts the job has juste been created

  It can be used as below:

    job = MyQueuetopia.create_job("mailer_queue", "deliver_mail", %{body: "hello", from: "from", to: "to"})

    assert_job_created(MyQueuetopia)
    assert_job_created(MyQueuetopia, "mailer_queue")
    assert_job_created(MyQueuetopia, "mailer_queue", %{params: %{body: "hello"}})
    assert_job_created(MyQueuetopia, "mailer_queue", %{action: "deliver_email", params: %{body: "hello"}})

  """

  def assert_job_created(queuetopia) when is_atom(queuetopia) do
    job = get_last_job(queuetopia)
    refute is_nil(job)
  end

  def assert_job_created(queuetopia, queue) when is_atom(queuetopia) and is_binary(queue) do
    job = get_last_job(queuetopia, queue)
    refute is_nil(job)
  end

  def assert_job_created(queuetopia, %{} = job) when is_atom(queuetopia) do
    last_job = get_last_job(queuetopia)
    refute is_nil(last_job)

    attrs = mapify(job)

    assert_job_attrs_match(last_job, attrs)
  end

  def assert_job_created(queuetopia, queue, %{} = job)
      when is_atom(queuetopia) and is_binary(queue) do
    last_job = get_last_job(queuetopia, queue)
    refute is_nil(last_job)

    attrs = mapify(job)

    assert_job_attrs_match(last_job, attrs)
  end

  defp assert_job_attrs_match(last_job, %{params: %{} = params} = attrs) do
    last_job_attrs = last_job |> Map.from_struct()

    assert MapSet.subset?(
             params |> MapSet.new(),
             last_job_attrs.params |> MapSet.new()
           ),
           """
           match failed
           found job: #{inspect(last_job)}
           match proposition:  #{inspect(attrs)}
           """

    assert_job_attrs_match(last_job, attrs |> Map.delete(:params))
  end

  defp assert_job_attrs_match(last_job, %{} = attrs) do
    last_job_attrs = last_job |> Map.from_struct()

    assert MapSet.subset?(attrs |> MapSet.new(), last_job_attrs |> MapSet.new()), """
      match failed
      found job: #{inspect(last_job)}
      match proposition:  #{inspect(attrs)}
    """
  end

  defp get_last_job(queuetopia) do
    repo = queuetopia.repo()

    Job |> Ecto.Query.last() |> repo.one()
  end

  defp get_last_job(queuetopia, queue) do
    repo = queuetopia.repo()

    Job
    |> Ecto.Query.where([job], job.queue == ^queue)
    |> Ecto.Query.last()
    |> repo.one()
  end

  defp mapify(%Job{} = job), do: job |> Map.from_struct() |> Map.delete(:__meta__)
  defp mapify(%{} = job), do: job
end
