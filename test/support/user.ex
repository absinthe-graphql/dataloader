defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field(:username, :string)
    has_many(:posts, Dataloader.Post)
    has_many(:comments, Dataloader.Comment)
    has_many(:commented_posts, through: [:comments, :post])
  end
end
