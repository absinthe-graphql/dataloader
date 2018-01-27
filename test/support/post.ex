defmodule Dataloader.Post do
  use Ecto.Schema

  schema "posts" do
    belongs_to(:user, Dataloader.User)
  end
end
