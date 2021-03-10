defmodule Dataloader.User do
  use Ecto.Schema

  schema "users" do
    field(:username, :string)
    has_many(:posts, Dataloader.Post)
    has_many(:published_posts, Dataloader.Post, where: [status: "published"])
    has_many(:published_posts_likes, through: [:published_posts, :likes])
    belongs_to(:leaderboard, Dataloader.Leaderboard)

    has_many(:scores, through: [:posts, :scores])
    has_many(:awarded_posts, through: [:scores, :post])
    has_many(:likes, through: [:awarded_posts, :likes])

    many_to_many(:liked_posts, Dataloader.Post, join_through: Dataloader.Like)

    many_to_many(:liked_published_posts, Dataloader.Post,
      join_through: Dataloader.Like,
      where: [status: "published"]
    )

    many_to_many(:published_liked_published_posts, Dataloader.Post,
      join_through: Dataloader.Like,
      where: [status: "published"],
      join_where: [status: "published"]
    )

    has_many(:fans, through: [:likes, :user])

    has_many(:liked_posts_scores, through: [:liked_posts, :scores])
    has_many(:liked_published_posts_scores, through: [:liked_published_posts, :scores])

    has_many(:published_liked_published_posts_scores,
      through: [:published_liked_published_posts, :scores]
    )

    many_to_many(:pictures, Dataloader.Picture, join_through: Dataloader.UserPicture)

    has_many(:published_picture_likes, through: [:pictures, :published_likes])

    many_to_many(:pictures_published, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_where: [status: "published"],
      where: [status: "published"]
    )

    many_to_many(:pictures_join_compare_value, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_where: [status: "published"]
    )

    many_to_many(:pictures_join_nil, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_where: [status: nil]
    )

    many_to_many(:pictures_join_in, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_where: [status: {:in, ["published", "blurry"]}]
    )

    many_to_many(:pictures_join_fragment, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      join_where: [status: {:fragment, "LENGTH(?) > 3"}]
    )

    many_to_many(:pictures_compare_value, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      where: [status: "published"]
    )

    many_to_many(:pictures_nil, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      where: [status: nil]
    )

    many_to_many(:pictures_in, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      where: [status: {:in, ["published", "blurry"]}]
    )

    many_to_many(:pictures_fragment, Dataloader.Picture,
      join_through: Dataloader.UserPicture,
      where: [status: {:fragment, "LENGTH(?) > 3"}]
    )
  end
end
