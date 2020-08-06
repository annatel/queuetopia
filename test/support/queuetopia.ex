defmodule Queuetopia.TestQueuetopia do
  use Queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end
