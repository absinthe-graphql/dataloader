defmodule Dataloader.Leaderboard do
  use Ecto.Schema

  schema "leaderboards" do
    field(:name, :string)
    has_many(:scores, Dataloader.Score)
  end
end
