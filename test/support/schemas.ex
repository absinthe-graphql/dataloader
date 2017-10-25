defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field :username, :string
  end
end

defmodule Dataloader.Post do
  use Ecto.Schema

  schema "users" do
    belongs_to :user, Dataloader.User
  end
end
