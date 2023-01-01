defmodule Queuetopia.MixProject do
  use Mix.Project

  @source_url "https://github.com/annatel/queuetopia"
  @version "2.4.3"

  def project do
    [
      app: :queuetopia,
      version: version(),
      elixir: "~> 1.12",
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
      {:ecto_sql, "~> 3.8"},
      {:jason, "~> 1.2"},
      {:myxql, ">= 0.0.0", only: :test},
      {:postgrex, ">= 0.0.0", only: :test},
      {:antl_utils_ecto, "~> 2.4"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "app.version": &display_app_version/1,
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

  defp version(), do: @version
  defp display_app_version(_), do: Mix.shell().info(version())
end
