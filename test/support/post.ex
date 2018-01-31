defmodule Dataloader.Post do
  use Ecto.Schema

  schema "posts" do
    belongs_to(:user, Dataloader.User)
    field(:title, :string)
    field(:deleted_at, :utc_datetime)
  end
end
