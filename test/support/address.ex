defmodule Dataloader.Address do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:city, :string)
    belongs_to(:country, Dataloader.Country)
  end
end
