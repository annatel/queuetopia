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

defmodule Queuetopia.TestQueuetopia_SchedulerRepo do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    scheduler_repo: Queuetopia.TestSchedulerRepo,
    performer: Queuetopia.TestPerfomer
end

defmodule Queuetopia.TestQueuetopia_Convention do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end

defmodule Queuetopia.TestQueuetopia_Convention.Performer do
  use Queuetopia.Performer
  import Queuetopia.Factory
  alias Queuetopia.Queue.Job

  @impl true
  def perform(%Job{queue: queue, id: job_id, params: %{"bin_pid" => bin_pid}}) do
    send(bin_to_pid(bin_pid), {queue, job_id, :performed_by_convention})
    :ok
  end
end

defmodule Queuetopia.TestQueuetopia_InMemSeq do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer

  def next_value!, do: Queuetopia.InMemorySequence.next_value!(TestInMemSeq)
end

defmodule Queuetopia.TestQueuetopiaThrowingInHandleFailedJob do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end

defmodule Queuetopia.TestQueuetopiaRaisingInHandleFailedJob do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end

defmodule Queuetopia.TestQueuetopiaErroringInHandleFailedJob do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end

defmodule Queuetopia.TestQueuetopiaExitingInHandleFailedJob do
  use Queuetopia,
    otp_app: :queuetopia,
    repo: Queuetopia.TestRepo,
    performer: Queuetopia.TestPerfomer
end
