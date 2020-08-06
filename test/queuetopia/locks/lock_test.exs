defmodule Queuetopia.Locks.LockTest do
  use Queuetopia.DataCase

  alias Queuetopia.Locks.Lock

  describe "changeset/2" do
    test "only permitted_keys are casted" do
      params = Factory.params_for(:lock)

      changeset = Lock.changeset(%Lock{}, Map.merge(params, %{new_key: "value"}))

      changes_keys = changeset.changes |> Map.keys()

      assert :scope in changes_keys
      assert :queue in changes_keys
      assert :locked_at in changes_keys
      assert :locked_by_node in changes_keys
      assert :locked_until in changes_keys
      refute :new_key in changes_keys
      assert Enum.count(changes_keys) == 5
    end

    test "when required params are missing, returns an invalid changeset" do
      changeset = Lock.changeset(%Lock{}, %{})

      refute changeset.valid?
      assert %{scope: ["can't be blank"]} = errors_on(changeset)
      assert %{queue: ["can't be blank"]} = errors_on(changeset)
      assert %{locked_at: ["can't be blank"]} = errors_on(changeset)
      assert %{locked_by_node: ["can't be blank"]} = errors_on(changeset)
      assert %{locked_until: ["can't be blank"]} = errors_on(changeset)
    end

    test "when a lock on a scoped queue already exists, returns a changeset error on insert" do
      %Lock{queue: queue, scope: scope} = Factory.insert(:lock)

      params = Factory.params_for(:lock, queue: queue, scope: scope)

      assert {:error, changeset} =
               Lock.changeset(%Lock{}, params)
               |> Queuetopia.TestRepo.insert()

      refute changeset.valid?
      assert %{queue: ["has already been taken"]} = errors_on(changeset)
    end

    test "when params are valid, return a valid changeset" do
      params = Factory.params_for(:lock)

      changeset = Lock.changeset(%Lock{}, params)

      assert changeset.valid?
      assert get_field(changeset, :scope) == params.scope
      assert get_field(changeset, :queue) == params.queue
      assert get_field(changeset, :locked_at) == params.locked_at
      assert get_field(changeset, :locked_by_node) == params.locked_by_node
      assert get_field(changeset, :locked_until) == params.locked_until
    end
  end
end
