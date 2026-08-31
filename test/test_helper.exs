{:ok, _pid} = Queuetopia.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Queuetopia.TestRepo, :manual)

{:ok, _pid} = Queuetopia.TestSchedulerRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Queuetopia.TestSchedulerRepo, :manual)

ExUnit.start()
