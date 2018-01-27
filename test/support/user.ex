defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field(:username, :string)
    has_many(:posts, Dataloader.Post)
  end
end
