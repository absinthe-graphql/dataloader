defmodule Dataloader.Mixfile do
  use Mix.Project

  @version "1.0.6"

  def project do
    [
      app: :dataloader,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      aliases: aliases(),
      source_url: "https://github.com/absinthe-graphql/dataloader",
      docs: [
        main: "Dataloader",
        source_ref: "v#{@version}",
        extras: [
          "CHANGELOG.md"
        ]
      ],
      deps: deps()
    ]
  end

  defp package do
    [
      description: "Efficient batch loading in Elixir",
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Ben Wilson"],
      licenses: ["MIT"],
      links: %{
        Changelog: "https://github.com/absinthe-graphql/dataloader/blob/master/CHANGELOG.md",
        GitHub: "https://github.com/absinthe-graphql/dataloader"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, ">= 0.0.0", optional: true},
      {:ecto_sql, "~> 3.0", optional: true, only: :test},
      {:postgrex, "~> 0.14", only: :test},
      {:dialyxir, "~> 0.5", only: :dev},
      {:ex_doc, ">= 0.0.0", only: [:dev]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
