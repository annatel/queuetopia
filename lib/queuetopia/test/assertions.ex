defmodule Queuetopia.Test.Assertions do
  import ExUnit.Assertions

  require Ecto.Query

  alias Queuetopia.Queue
  alias Queuetopia.Queue.Job

  @doc """
  Find jobs that have just been created

  It can be used as below:

    # Examples
        MyQueuetopia.create_job("mailer_queue", "deliver_mail", %{body: "hello", from: "from", to: "to"})

        assert [job] = jobs_created(MyQueuetopia)
  """
  def jobs_created(queuetopia, %{} = job_attrs \\ %{}) do
    job_attrs = full_job_attrs(queuetopia, job_attrs)

    job_params = Map.get(job_attrs, :params, %{})

    Queue.list_jobs(queuetopia.repo(),
      filters: job_attrs |> Map.take(filterable_fields()) |> Enum.to_list()
    )
    |> Enum.filter(fn job -> subset?(job_params, job.params) end)
    |> mapify()
  end

  defp full_job_attrs(queuetopia, job_attrs),
    do: job_attrs |> Map.put(:scope, to_string(queuetopia)) |> mapify()

  @doc """
  Asserts the job has juste been created

  It can be used as below:

    # Examples
        job = MyQueuetopia.create_job("mailer_queue", "deliver_mail", %{body: "hello", from: "from", to: "to"})

        assert_job_created(MyQueuetopia)
        assert_job_created(MyQueuetopia, 1)
        assert_job_created(MyQueuetopia, %{queue: "mailer_queue", params: %{body: "hello"}})
        assert_job_created(MyQueuetopia, 2, %{action: "deliver_email", params: %{body: "hello"}})

  """
  def assert_job_created(queuetopia, job_attrs \\ %{})

  def assert_job_created(queuetopia, %{} = job_attrs),
    do: assert_job_created(queuetopia, 1, job_attrs)

  def assert_job_created(queuetopia, expected_count) when is_integer(expected_count),
    do: assert_job_created(queuetopia, expected_count, %{})

  def assert_job_created(queuetopia, expected_count, %{} = job_attrs)
      when is_integer(expected_count) do
    count = jobs_created(queuetopia, job_attrs) |> length()

    assert count == expected_count,
           message("job", full_job_attrs(queuetopia, job_attrs), expected_count, count)
  end

  defp filterable_fields(), do: [:id, :scope, :queue, :action]

  defp subset?(a, b) do
    MapSet.subset?(a |> MapSet.new(), b |> MapSet.new())
  end

  @doc """
  Refute that a job has been created.

  It can be used as below:

    # Examples
        job = MyQueuetopia.create_job("mailer_queue", "deliver_mail", %{body: "hello", from: "from", to: "to"})

        refute_job_created(MyQueuetopia)
        refute_job_created(MyQueuetopia, %{queue: "mailer_queue", params: %{body: "hello"}})

  """
  def refute_job_created(queuetopia, %{} = job_attrs \\ %{}) do
    assert_job_created(queuetopia, 0, job_attrs)
  end

  defp mapify(jobs) when is_list(jobs), do: Enum.map(jobs, &mapify/1)
  defp mapify(%Job{} = job), do: job |> Map.from_struct() |> Map.delete(:__meta__)
  defp mapify(%{} = job), do: job

  defp message(
         resource_name,
         %{} = expected_job_attrs,
         expected_count,
         found_count
       ) do
    if Enum.empty?(expected_job_attrs |> Map.drop([:scope])),
      do:
        "Expected #{expected_count} #{maybe_pluralized_item(resource_name, expected_count)}, got #{found_count}",
      else:
        "Expected #{expected_count} #{maybe_pluralized_item(resource_name, expected_count)} with attributes #{inspect(expected_job_attrs, pretty: true)}, got #{found_count}."
  end

  defp maybe_pluralized_item(resource_name, count) when count > 1, do: resource_name <> "s"
  defp maybe_pluralized_item(resource_name, _), do: resource_name
end
