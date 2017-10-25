use Mix.Config

config :dataloader, Dataloader.TestRepo,
  hostname: "localhost",
  database: "dataloader_test",
  adapter: Ecto.Adapters.Postgres,
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warn
