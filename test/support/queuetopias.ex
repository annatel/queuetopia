defmodule Queuetopia.TestQueuetopia do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end

defmodule Queuetopia.TestQueuetopia_2 do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end

defmodule Queuetopia.TestQueuetopia_RedefTest do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerformer

  @impl true
  def next_value!, do: 666
end

defmodule Queuetopia.TestQueuetopia_InMemSeq do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer

  def next_value!, do: Queuetopia.InMemorySequence.next_value!(TestInMemSeq)
end
