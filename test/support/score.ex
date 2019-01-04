defmodule Dataloader.Score do
  use Ecto.Schema

  schema "scores" do
    belongs_to(:post, Dataloader.Post)
    belongs_to(:leaderboard, Dataloader.Leaderboard)
  end
end
