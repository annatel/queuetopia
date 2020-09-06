defmodule Queuetopia.Jobs.JobTest do
  use Queuetopia.DataCase

  alias Queuetopia.Jobs.Job

  describe "create_changeset/2" do
    test "only permitted_keys are casted" do
      params =
        Factory.params_for(:job,
          timeout: 100,
          max_backoff: 100,
          max_attempts: 1
        )

      changeset = Job.create_changeset(Map.merge(params, %{new_key: "value"}))

      changes_keys = changeset.changes |> Map.keys()

      assert :sequence in changes_keys
      assert :scope in changes_keys
      assert :queue in changes_keys
      assert :performer in changes_keys
      assert :action in changes_keys
      assert :params in changes_keys
      assert :timeout in changes_keys
      assert :max_backoff in changes_keys
      assert :max_attempts in changes_keys
      assert :scheduled_at in changes_keys
      refute :new_key in changes_keys
      assert Enum.count(changes_keys) == 10

      assert changeset.valid?
    end

    test "timing params default values" do
      params =
        Factory.params_for(:job,
          timeout: nil,
          max_backoff: nil,
          max_attempts: nil
        )

      changeset = Job.create_changeset(Map.merge(params, %{new_key: "value"}))
      assert Ecto.Changeset.get_field(changeset, :timeout) == Job.default_timeout()
      assert Ecto.Changeset.get_field(changeset, :max_backoff) == Job.default_max_backoff()
      assert Ecto.Changeset.get_field(changeset, :max_attempts) == Job.default_max_attempts()

      assert changeset.valid?
    end

    test "when required params are missing, returns an invalid changeset" do
      changeset = Job.create_changeset(%{timeout: nil, max_backoff: nil, max_attempts: nil})

      refute changeset.valid?
      assert %{sequence: ["can't be blank"]} = errors_on(changeset)
      assert %{scope: ["can't be blank"]} = errors_on(changeset)
      assert %{queue: ["can't be blank"]} = errors_on(changeset)
      assert %{performer: ["can't be blank"]} = errors_on(changeset)
      assert %{action: ["can't be blank"]} = errors_on(changeset)
      assert %{params: ["can't be blank"]} = errors_on(changeset)
      assert %{scheduled_at: ["can't be blank"]} = errors_on(changeset)
      assert %{timeout: ["can't be blank"]} = errors_on(changeset)
      assert %{max_backoff: ["can't be blank"]} = errors_on(changeset)
      assert %{max_attempts: ["can't be blank"]} = errors_on(changeset)
    end

    test "when timing params are lesser than or equal to 0 are not valid, return a invalid changeset" do
      params =
        Factory.params_for(:job,
          timeout: -1,
          max_backoff: -1,
          max_attempts: -1
        )

      changeset = Job.create_changeset(params)

      refute changeset.valid?
      assert %{timeout: ["must be greater than or equal to 0"]} = errors_on(changeset)

      assert %{max_backoff: ["must be greater than or equal to 0"]} = errors_on(changeset)

      assert %{max_attempts: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "when timing params are not valid, return a invalid changeset" do
      params =
        Factory.params_for(:job,
          timeout: 0.4,
          max_backoff: 0.4,
          max_attempts: 0.4
        )

      changeset = Job.create_changeset(params)

      refute changeset.valid?
      assert %{timeout: ["is invalid"]} = errors_on(changeset)
      assert %{max_backoff: ["is invalid"]} = errors_on(changeset)
      assert %{max_attempts: ["is invalid"]} = errors_on(changeset)
    end

    test "when params are valid, return a valid changeset" do
      params =
        Factory.params_for(:job,
          timeout: 100,
          max_backoff: 100,
          max_attempts: 1
        )

      changeset = Job.create_changeset(params)

      assert changeset.valid?
      assert get_field(changeset, :queue) == params.queue
      assert get_field(changeset, :scope) == params.scope
      assert get_field(changeset, :performer) == params.performer
      assert get_field(changeset, :action) == params.action
      assert get_field(changeset, :params) == params.params
      assert get_field(changeset, :timeout) == params.timeout

      assert get_field(changeset, :max_backoff) ==
               params.max_backoff

      assert get_field(changeset, :max_attempts) == params.max_attempts
    end
  end

  describe "failed_job_changeset/2" do
    test "only permitted_keys are casted" do
      job = Factory.insert(:job)

      params =
        Factory.params_for(:job,
          attempts: 6,
          attempted_at: Factory.utc_datetime(),
          attempted_by: Atom.to_string(Node.self()),
          scheduled_at: Factory.utc_datetime(),
          error: "error"
        )

      changeset = Job.failed_job_changeset(job, Map.merge(params, %{new_key: "value"}))
      changes_keys = changeset.changes |> Map.keys()

      assert :attempts in changes_keys
      assert :attempted_at in changes_keys
      assert :attempted_by in changes_keys
      assert :scheduled_at in changes_keys
      assert :error in changes_keys
      assert Enum.count(changes_keys) == 5

      refute :new_key in changes_keys
    end

    test "when required params are missing, returns an invalid changeset" do
      job = Factory.insert(:job)

      changeset = Job.failed_job_changeset(job, %{attempts: nil, scheduled_at: nil})

      refute changeset.valid?
      assert %{attempts: ["can't be blank"]} = errors_on(changeset)
      assert %{attempted_at: ["can't be blank"]} = errors_on(changeset)
      assert %{attempted_by: ["can't be blank"]} = errors_on(changeset)
      assert %{scheduled_at: ["can't be blank"]} = errors_on(changeset)
      assert %{error: ["can't be blank"]} = errors_on(changeset)
    end

    test "when params are valid, return a valid changeset" do
      utc_datetime = Factory.utc_datetime()
      job = Factory.insert(:job)

      changeset =
        Job.failed_job_changeset(job, %{
          attempts: 1,
          attempted_at: utc_datetime,
          attempted_by: Atom.to_string(Node.self()),
          scheduled_at: utc_datetime,
          error: "error"
        })

      assert changeset.valid?
    end
  end

  describe "succeeded_job_changeset/2" do
    test "only permitted_keys are casted" do
      job = Factory.insert(:job)

      params =
        Factory.params_for(:job,
          attempts: 6,
          attempted_at: Factory.utc_datetime(),
          attempted_by: Atom.to_string(Node.self()),
          done_at: Factory.utc_datetime()
        )

      changeset = Job.succeeded_job_changeset(job, Map.merge(params, %{new_key: "value"}))
      changes_keys = changeset.changes |> Map.keys()

      assert :attempts in changes_keys
      assert :attempted_at in changes_keys
      assert :attempted_by in changes_keys
      assert :done_at in changes_keys
      assert Enum.count(changes_keys) == 4

      refute :new_key in changes_keys
    end

    test "when required params are missing, returns an invalid changeset" do
      job = Factory.insert(:job)

      changeset = Job.succeeded_job_changeset(job, %{attempts: nil})
      refute changeset.valid?
      assert %{attempts: ["can't be blank"]} = errors_on(changeset)
      assert %{attempted_at: ["can't be blank"]} = errors_on(changeset)
      assert %{attempted_by: ["can't be blank"]} = errors_on(changeset)
      assert %{done_at: ["can't be blank"]} = errors_on(changeset)
    end

    test "nillifies error field" do
      job = Factory.insert(:job, error: "error")

      params =
        Factory.params_for(:job,
          attempts: 6,
          attempted_at: Factory.utc_datetime(),
          attempted_by: Atom.to_string(Node.self()),
          done_at: Factory.utc_datetime()
        )

      changeset = Job.succeeded_job_changeset(job, params)

      assert is_nil(changeset.changes.error)
    end

    test "when params are valid, return a valid changeset" do
      utc_datetime = Factory.utc_datetime()
      job = Factory.insert(:job)

      changeset =
        Job.succeeded_job_changeset(job, %{
          attempts: 1,
          attempted_at: utc_datetime,
          attempted_by: Atom.to_string(Node.self()),
          done_at: utc_datetime
        })

      assert changeset.valid?
    end
  end
end
