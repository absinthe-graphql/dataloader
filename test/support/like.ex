defmodule Dataloader.Like do
  use Ecto.Schema

  schema "likes" do
    belongs_to(:user, Dataloader.User)
    belongs_to(:post, Dataloader.Post)
    belongs_to(:picture, Dataloader.Picture)
    field(:status, :string)
  end
end
