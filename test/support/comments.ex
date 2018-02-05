defmodule Dataloader.Comment do
  use Ecto.Schema

  schema "comments" do
    belongs_to(:post, Dataloader.Post)
    belongs_to(:user, Dataloader.User)
  end
end
