defmodule Queuetopia.Test.Assertions do
  import ExUnit.Assertions
  require Ecto.Query
  alias Queuetopia.Queue.Job

  @doc """
  Asserts the job has juste been created

  It can be used as below:

    # Examples
        job = MyQueuetopia.create_job("mailer_queue", "deliver_mail", %{body: "hello", from: "from", to: "to"})

        assert_job_created(MyQueuetopia)
        assert_job_created(MyQueuetopia, "mailer_queue")
        assert_job_created(MyQueuetopia, "mailer_queue", %{params: %{body: "hello"}})
        assert_job_created(MyQueuetopia, "mailer_queue", %{action: "deliver_email", params: %{body: "hello"}})

  """

  def assert_job_created(queuetopia) when is_atom(queuetopia) do
    job = get_last_job(queuetopia)
    refute is_nil(job), expected_job_message(%{scope: queuetopia |> to_string}, job)
  end

  def assert_job_created(queuetopia, queue) when is_atom(queuetopia) and is_binary(queue) do
    job = get_last_job(queuetopia, queue)
    refute is_nil(job), expected_job_message(%{scope: queuetopia |> to_string, queue: queue}, job)
  end

  def assert_job_created(queuetopia, %{} = job_params) when is_atom(queuetopia) do
    last_job = get_last_job(queuetopia)
    refute is_nil(last_job), expected_job_message(job_params, last_job)

    attrs = mapify(job_params)

    assert_job_attrs_match(last_job, attrs)
  end

  def assert_job_created(queuetopia, queue, %{} = job_params)
      when is_atom(queuetopia) and is_binary(queue) do
    last_job = get_last_job(queuetopia, queue)
    refute is_nil(last_job), expected_job_message(job_params, last_job)

    attrs = mapify(job_params)

    assert_job_attrs_match(last_job, attrs)
  end

  defp assert_job_attrs_match(last_job, %{params: %{} = params} = attrs) do
    last_job_attrs = last_job |> Map.from_struct()

    assert subset?(params, last_job_attrs.params) and
             subset?(attrs |> Map.delete(:params), last_job_attrs),
           expected_job_message(attrs, last_job)
  end

  defp assert_job_attrs_match(last_job, %{} = attrs) do
    last_job_attrs = last_job |> Map.from_struct()

    assert subset?(attrs, last_job_attrs), expected_job_message(attrs, last_job)
  end

  defp subset?(a, b) do
    MapSet.subset?(a |> MapSet.new(), b |> MapSet.new())
  end

  defp expected_job_message(expected_job_attrs, found_job) do
    """
    Expected a job matching:

    #{inspect(expected_job_attrs, pretty: true)}

    Found job: #{inspect(found_job, pretty: true)}
    """
  end

  @doc """
  Refute that a job has been created.
  """
  def refute_job_created(queuetopia) do
    job = get_last_job(queuetopia)
    assert is_nil(job), no_expected_job_message(%{scope: queuetopia |> to_string}, job)
  end

  def refute_job_created(queuetopia, queue) when is_atom(queuetopia) and is_binary(queue) do
    job = get_last_job(queuetopia, queue)

    assert is_nil(job),
           no_expected_job_message(%{scope: queuetopia |> to_string, queue: queue}, job)
  end

  def refute_job_created(queuetopia, %{} = job_params) when is_atom(queuetopia) do
    last_job = get_last_job(queuetopia)
    assert is_nil(last_job), no_expected_job_message(job_params, last_job)
  end

  def refute_job_created(queuetopia, queue, %{} = job_params)
      when is_atom(queuetopia) and is_binary(queue) do
    last_job = get_last_job(queuetopia, queue)
    assert is_nil(last_job), no_expected_job_message(job_params, last_job)
  end

  defp no_expected_job_message(expected_job_attrs, found_job) do
    """
    Expected no job matching:

    #{inspect(expected_job_attrs, pretty: true)}

    Found job: #{inspect(found_job, pretty: true)}
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
