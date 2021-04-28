defmodule Queuetopia.TestRepo do
  use Ecto.Repo,
    otp_app: :queuetopia,
    adapter:
      if(Application.get_env(:queuetopia, :use_mysql_adapter?),
        do: Ecto.Adapters.MyXQL,
        else: Ecto.Adapters.Postgres
      )
end
