defmodule Queuetopia.MixProject do
  use Mix.Project

  @source_url "https://github.com/annatel/queuetopia"
  @version "0.6.3"

  def project do
    [
      app: :queuetopia,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      package: package(),
      description: description(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      docs: docs()
    ]
  end

  defp description() do
    "the blocking job queue"
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.4"},
      {:myxql, "~> 0.4.0", only: :test},
      {:jason, "~> 1.0"},
      {:antl_utils_elixir, "~> 0.2.0"},
      {:ex_machina, "~> 2.4", only: :test},
      {:mox, "~> 0.5", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: [
        "README.md"
      ]
    ]
  end
end
