import Config

if(Mix.env() == :test) do
  config :logger, level: System.get_env("EX_LOG_LEVEL", "warn") |> String.to_atom()

  config :queuetopia, ecto_repos: [Queuetopia.TestRepo]

  config :queuetopia,
    use_postgres_adapter?: System.get_env("QUEUETOPIA__DATABASE_TEST_ADAPTER") in ["postgres"]

  config :queuetopia, Queuetopia.TestRepo,
    url: System.get_env("QUEUETOPIA__DATABASE_TEST_URL"),
    pool: Ecto.Adapters.SQL.Sandbox
end
