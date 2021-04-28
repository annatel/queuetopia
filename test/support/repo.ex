defmodule Queuetopia.TestRepo do
  use Ecto.Repo,
    otp_app: :queuetopia,
    adapter:
      if(Application.get_env(:queuetopia, :use_postgres_adapter?),
        do: Ecto.Adapters.Postgres,
        else: Ecto.Adapters.MyXQL
      )
end
