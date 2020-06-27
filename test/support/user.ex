defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field(:username, :string)
    has_many(:posts, Dataloader.Post)
    belongs_to(:leaderboard, Dataloader.Leaderboard)

    has_many(:scores, through: [:posts, :scores])
    has_many(:awarded_posts, through: [:scores, :post])
    has_many(:likes, through: [:awarded_posts, :likes])
    many_to_many(:liked_posts, Dataloader.Post, join_through: Dataloader.Like)
    has_many(:fans, through: [:likes, :user])
  end
end
