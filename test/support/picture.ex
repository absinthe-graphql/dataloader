defmodule Dataloader.Picture do
  use Ecto.Schema

  schema "pictures" do
    field :url, :string, null: false
  end
end
