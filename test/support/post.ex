defmodule Dataloader.Post do
  use Ecto.Schema

  schema "posts" do
    belongs_to(:user, Dataloader.User)
    has_many(:likes, Dataloader.Like)
    has_many(:scores, Dataloader.Score)
    has_many(:liking_users, through: [:likes, :user])

    field(:title, :string)
    field(:status, :string)
    field(:deleted_at, :utc_datetime)
  end
end
