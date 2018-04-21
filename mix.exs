defmodule Dataloader.Mixfile do
  use Mix.Project

  @version "2.0.1"

  def project do
    [
      app: :dataloader,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      aliases: aliases(),
      docs: [source_ref: "v#{@version}", main: "Dataloader"],
      deps: deps()
    ]
  end

  defp package do
    [
      name: :lazyloader,
      description: "Efficient batch loading in Elixir",
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Ben Wilson", "Jaap Frolich"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/absinthe-graphql/dataloader"}
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
      {:ex_doc, ">= 0.0.0", only: [:dev]},
      {:defer, ">= 0.1.1"}
      # {:defer, github: "jfrolich/deferred"}
      # {:defer, path: "../defer"}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
