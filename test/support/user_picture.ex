defmodule Dataloader.UserPicture do
  use Ecto.Schema

  schema "user_pictures" do
    field(:status, :string)
    belongs_to(:picture, Dataloader.Picture)
    belongs_to(:user, Dataloader.User)
  end
end
