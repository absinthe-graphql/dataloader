defmodule Dataloader.Country do
  use Ecto.Schema

  schema "countries" do
    field(:name, :string)
  end
end
