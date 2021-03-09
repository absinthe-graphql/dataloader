defmodule Dataloader.Picture do
  use Ecto.Schema

  schema "pictures" do
    field(:status, :string)
    field(:url, :string, null: false)
    has_many(:likes, Dataloader.Like)
  end
end
