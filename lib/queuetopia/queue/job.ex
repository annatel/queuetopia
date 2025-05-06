defmodule Queuetopia.Queue.Job do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset,
    only: [
      cast: 3,
      put_change: 3,
      validate_number: 3,
      validate_required: 2,
      validate_inclusion: 3
    ]

  @type t :: %__MODULE__{}
  @type option ::
          {:timeout, non_neg_integer()}
          | {:max_backoff, non_neg_integer()}
          | {:max_attempts, non_neg_integer()}

  @default_timeout 60 * 1_000
  @default_max_backoff 24 * 3600 * 1_000
  @default_max_attempts 20

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "queuetopia_jobs" do
    field(:sequence, :integer)
    field(:scope, :string)
    field(:queue, :string)
    field(:performer, :string)
    field(:action, :string)
    field(:params, :map)
    field(:timeout, :integer, default: @default_timeout)
    field(:max_backoff, :integer, default: @default_max_backoff)
    field(:max_attempts, :integer, default: @default_max_attempts)

    field(:scheduled_at, :utc_datetime)
    field(:attempts, :integer, default: 0)
    field(:attempted_at, :utc_datetime)
    field(:attempted_by, :string)
    field(:next_attempt_at, :utc_datetime)
    field(:ended_at, :utc_datetime)
    field(:end_status, :string)
    field(:error, :string)

    timestamps(type: :utc_datetime)
  end

  def default_timeout(), do: @default_timeout
  def default_max_backoff(), do: @default_max_backoff
  def default_max_attempts(), do: @default_max_attempts

  @spec create_changeset(map) :: Ecto.Changeset.t()
  def create_changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :sequence,
      :scope,
      :queue,
      :performer,
      :action,
      :params,
      :timeout,
      :max_backoff,
      :max_attempts,
      :scheduled_at
    ])
    |> validate_required([
      :sequence,
      :scope,
      :queue,
      :performer,
      :action,
      :params,
      :timeout,
      :max_backoff,
      :max_attempts,
      :scheduled_at
    ])
    |> validate_number(:timeout, greater_than_or_equal_to: 0)
    |> validate_number(:max_backoff, greater_than_or_equal_to: 0)
    |> validate_number(:max_attempts, greater_than_or_equal_to: 0)
  end

  @spec retry_job_changeset(Job.t(), map) :: Ecto.Changeset.t()
  def retry_job_changeset(%__MODULE__{} = job, attrs) when is_map(attrs) do
    job
    |> cast(attrs, [:attempts, :attempted_at, :attempted_by, :next_attempt_at, :error])
    |> validate_required_attempt_attributes
    |> validate_required([:next_attempt_at, :error])
  end

  @spec failed_job_changeset(Job.t(), map) :: Ecto.Changeset.t()
  def failed_job_changeset(%__MODULE__{} = job, attrs) when is_map(attrs) do
    job
    |> cast(attrs, [:attempts, :attempted_at, :attempted_by, :ended_at, :end_status, :error])
    |> validate_required_attempt_attributes
    |> validate_required([:ended_at, :end_status, :error])
    |> validate_inclusion(:end_status, ["failed", "max_attempts_reached"])
  end

  @spec aborted_job_changeset(Job.t(), map) :: Ecto.Changeset.t()
  def aborted_job_changeset(%__MODULE__{} = job, attrs) when is_map(attrs) do
    job
    |> cast(attrs, [:ended_at])
    |> validate_required([:ended_at])
    |> put_change(:end_status, "aborted")
  end

  @spec succeeded_job_changeset(Job.t(), map) :: Ecto.Changeset.t()
  def succeeded_job_changeset(%__MODULE__{} = job, attrs) when is_map(attrs) do
    job
    |> cast(attrs, [:attempts, :attempted_at, :attempted_by, :ended_at])
    |> validate_required_attempt_attributes
    |> validate_required([:ended_at])
    |> put_change(:end_status, "success")
    |> put_change(:error, nil)
  end

  defp validate_required_attempt_attributes(changeset) do
    changeset
    |> validate_required([:attempts, :attempted_at, :attempted_by])
  end

  def email_subject(%__MODULE__{} = job) do
    "[#{job.scope} - Failed job (#{job.id})]"
  end

  def email_html_body(%__MODULE__{} = job) do
    """
    ==============================<br/>
    <br/>
    Hi,<br/>
    <br/>
    Here is a report about a job failure.<br/>
    <br/>
    Id: #{job.id}<br/>
    Scope: #{job.scope}<br/>
    Queue: #{job.queue}<br/>
    Action: #{job.action}<br/>
    Job parameters: #{inspect(job.params)}<br/>
    Number of attempts: #{job.attempts}<br/>
    Next attempt at: #{job.next_attempt_at}<br/>
    Error: #{job.error}<br/>
    <br/>
    Please, fix the failure in order to unlock the flow of the jobs.<br/>
    <br/>
    ==============================
    """
  end
end
