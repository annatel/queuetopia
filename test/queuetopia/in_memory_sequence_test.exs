defmodule Queuetopia.InMemorySequencesTest do
  use Queuetopia.DataCase

  alias Queuetopia.InMemorySequence
  alias Queuetopia.TestQueuetopia_InMemSeq

  defp start_test_in_mem_seq do
    start_supervised!({InMemorySequence, name: TestInMemSeq, repo: Queuetopia.TestRepo})
  end

  describe "in memory sequence" do
    test "starts ok" do
      pid = start_supervised!({InMemorySequence, repo: Queuetopia.TestRepo})
      assert is_pid(pid)
    end

    test "can be started with name" do
      started_pid = start_supervised!({InMemorySequence, name: PwetPwet, repo: Queuetopia.TestRepo})
      assert started_pid == Process.whereis(PwetPwet)
    end

    test "get next value" do
      pid = start_supervised!({InMemorySequence, name: Plop, repo: Queuetopia.TestRepo})

      assert 1 = InMemorySequence.next_value!(Plop)
      assert 2 = InMemorySequence.next_value!(pid)
    end

    test "get next value via specific queutopia" do
      start_test_in_mem_seq()

      assert 1 = TestQueuetopia_InMemSeq.next_value!()
      assert 2 = TestQueuetopia_InMemSeq.next_value!()
    end

    test "start with max sequence" do
      insert!(:job, sequence: 100)

      start_test_in_mem_seq()

      assert 101 = TestQueuetopia_InMemSeq.next_value!()
    end
  end
end
