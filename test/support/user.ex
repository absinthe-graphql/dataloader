defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field(:username, :string)
    has_many(:posts, Dataloader.Post)
    belongs_to(:leaderboard, Dataloader.Leaderboard)

    has_many(:scores, through: [:posts, :scores])
    has_many(:awarded_posts, through: [:scores, :post])
    has_many(:likes, through: [:awarded_posts, :likes])
    many_to_many(:liked_posts, Dataloader.Post, join_through: Dataloader.Like)
    has_many(:fans, through: [:likes, :user])

    many_to_many(:pictures_join_compare_value, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      join_where: [status: "published"]
    )

    many_to_many(:pictures_join_nil, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      join_where: [status: nil]
    )

    many_to_many(:pictures_join_in, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      join_where: [status: {:in, ["published", "blurry"]}]
    )

    many_to_many(:pictures_join_fragment, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      join_where: [status: {:fragment, "LENGTH(?) > 3"}]
    )

    many_to_many(:pictures_compare_value, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      where: [status: "published"]
    )

    many_to_many(:pictures_nil, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      where: [status: nil]
    )

    many_to_many(:pictures_in, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      where: [status: {:in, ["published", "blurry"]}]
    )

    many_to_many(:pictures_fragment, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_keys: [user_id: :id, picture_id: :id],
      where: [status: {:fragment, "LENGTH(?) > 3"}]
    )
  end
end
