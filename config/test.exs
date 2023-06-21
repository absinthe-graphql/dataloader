import Config

config :dataloader, Dataloader.TestRepo,
  hostname: "localhost",
  username: "postgres",
  password: "postgres",
  database: "dataloader_test",
  pool: Ecto.Adapters.SQL.Sandbox

config :dataloader, ecto_repos: [Dataloader.TestRepo]

config :logger, level: :warn
