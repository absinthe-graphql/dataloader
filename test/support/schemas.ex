defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field :username, :string
    has_many :posts, Dataloader.Post
  end
end

defmodule Dataloader.Post do
  use Ecto.Schema

  schema "posts" do
    belongs_to :user, Dataloader.User
  end
end
