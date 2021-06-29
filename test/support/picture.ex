defmodule Dataloader.Picture do
  use Ecto.Schema

  schema "pictures" do
    field(:status, :string)
    field(:url, :string, null: false)
    has_many(:likes, Dataloader.Like)
    has_many(:published_likes, Dataloader.Like, where: [status: "published"])
  end
end
