defmodule Queuetopia.TestQueuetopia_2 do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end
