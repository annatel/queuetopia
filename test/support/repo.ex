defmodule Queuetopia.TestRepo do
  @test_repo_adapter Application.get_env(:queuetopia, :test_repo_adapter)
  @test_repo_adapter_options %{
    "myxql" => Ecto.Adapters.MyXQL,
    "postgres" => Ecto.Adapters.Postgres
  }

  use Ecto.Repo,
    otp_app: :queuetopia,
    adapter: @test_repo_adapter_options[@test_repo_adapter]
end
