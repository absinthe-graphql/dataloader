defmodule Dataloader.Mixfile do
  use Mix.Project

  @source_url "https://github.com/absinthe-graphql/dataloader"
  @version "2.0.0-dev"

  def project do
    [
      app: :dataloader,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      preferred_cli_env: [
        dialyzer: :test
      ],
      dialyzer: [
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :ecto, :ecto_sql]
      ]
    ]
  end

  defp package do
    [
      description: "Efficient batch loading in Elixir",
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Ben Wilson"],
      licenses: ["MIT"],
      links: %{
        Changelog: "https://hexdocs.pm/dataloader/changelog.html",
        GitHub: @source_url
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger] ++ test_apps(Mix.env())
    ]
  end

  # TODO: After Elixir 1.8, optional dependencies will be automatically
  # included in `extra_applications`. So, it will be safe to remove this
  # section.
  #
  # See: https://github.com/elixir-lang/elixir/pull/8263
  defp test_apps(:test) do
    [:ecto_sql, :postgrex]
  end

  defp test_apps(_), do: []

  defp deps do
    [
      {:telemetry, "~> 1.0 or ~> 0.4"},
      {:ecto, ">= 3.4.3 and < 4.0.0", optional: true},
      {:ecto_sql, "~> 3.0", optional: true, only: :test},
      {:postgrex, "~> 0.14", only: :test, runtime: false},
      {:dialyxir, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end

  def docs do
    [
      extras: [
        "CHANGELOG.md",
        "README.md",
        "guides/telemetry.md"
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
