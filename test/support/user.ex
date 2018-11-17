defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field(:username, :string)
    has_many(:posts, Dataloader.Post)
    belongs_to(:leaderboard, Dataloader.Leaderboard)

    has_many(:scores, through: [:leaderboard, :scores])
    has_many(:awarded_posts, through: [:scores, :post])
  end
end
