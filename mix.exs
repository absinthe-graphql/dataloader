defmodule Dataloader.Mixfile do
  use Mix.Project

  def project do
    [
      app: :dataloader,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      elixirc_paths: elixirc_paths(Mix.env),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger] ++ test_apps(Mix.env)
    ]
  end

  defp test_apps(:test) do
    [:ecto, :postgrex]
  end
  defp test_apps(_), do: []

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, ">= 0.0.0", optional: true},
      {:postgrex, ">= 0.0.0", only: :test},
      {:dialyxir, "~> 0.5", only: :dev},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end
end
