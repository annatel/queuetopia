defmodule Queuetopia.TestRepo do
  use Ecto.Repo,
    otp_app: :queuetopia,
    adapter: Ecto.Adapters.MyXQL
end
