{:ok, _pid} = Queuetopia.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Queuetopia.TestRepo, :manual)

ExUnit.start()
