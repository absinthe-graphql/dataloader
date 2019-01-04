defmodule Dataloader.TestRepo do
  use Ecto.Repo,
    otp_app: :dataloader,
    adapter: Ecto.Adapters.Postgres
end
