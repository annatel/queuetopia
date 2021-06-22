defmodule Queuetopia.MixProject do
  use Mix.Project

  @source_url "https://github.com/annatel/queuetopia"
  @version "2.0.1"

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
    "Persistent blocking job queue"
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.6"},
      {:jason, "~> 1.2"},
      {:myxql, "~> 0.4.0", only: :test},
      {:postgrex, ">= 0.0.0", only: :test},
      {:antl_utils_ecto, "2.3.2"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
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
