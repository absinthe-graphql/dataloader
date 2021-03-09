defmodule Dataloader.Ecto.HasManyThroughManyToManyTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post, Score, Like, Picture, UserPicture}
  import Ecto.Query
  alias Dataloader.TestRepo, as: Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    test_pid = self()

    source =
      Dataloader.Ecto.new(
        Repo,
        query: &query(&1, &2, test_pid)
      )

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Test, source)

    {:ok, loader: loader}
  end

  defp query(schema, %{limit: limit}, test_pid) do
    send(test_pid, :querying)

    schema
    |> limit(^limit)
  end

  describe "has_many through many-to-many associations" do
    test "load has_many through many_to_many", %{loader: loader} do
      leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
      user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()

      post1 = %Post{user_id: user1.id, title: "foo"} |> Repo.insert!()

      score1 = %Score{post_id: post1.id, leaderboard_id: leaderboard.id} |> Repo.insert!()

      %Like{user_id: user1.id, post_id: post1.id} |> Repo.insert!()

      args = {:liked_posts_scores, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [score1] == Dataloader.get(loader, Test, args, user1)
    end

    test "load has_many through many_to_many - with where on target schema", %{loader: loader} do
      leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
      user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()

      post1 = %Post{user_id: user1.id, title: "pub_post", status: "published"} |> Repo.insert!()
      post2 = %Post{user_id: user1.id, title: "unpub_post"} |> Repo.insert!()

      score1 = %Score{post_id: post1.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
      _score2 = %Score{post_id: post2.id, leaderboard_id: leaderboard.id} |> Repo.insert!()

      %Like{user_id: user1.id, post_id: post1.id} |> Repo.insert!()
      %Like{user_id: user1.id, post_id: post2.id} |> Repo.insert!()

      args = {:liked_published_posts_scores, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [score1] == Dataloader.get(loader, Test, args, user1)
    end

    test "load has_many through many_to_many - with where on target schema and join_where on assoc schema",
         %{loader: loader} do
      leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
      user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()

      post1 =
        %Post{user_id: user1.id, title: "published_post", status: "published"} |> Repo.insert!()

      post2 =
        %Post{user_id: user1.id, title: "published_post", status: "published"} |> Repo.insert!()

      post3 =
        %Post{user_id: user1.id, title: "unpublished_post", status: "unpublished"}
        |> Repo.insert!()

      _score1 = %Score{post_id: post1.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
      score2 = %Score{post_id: post2.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
      _score3 = %Score{post_id: post3.id, leaderboard_id: leaderboard.id} |> Repo.insert!()

      %Like{user_id: user1.id, post_id: post1.id, status: "unpublished"} |> Repo.insert!()
      %Like{user_id: user1.id, post_id: post2.id, status: "published"} |> Repo.insert!()
      %Like{user_id: user1.id, post_id: post3.id} |> Repo.insert!()

      args = {:published_liked_published_posts_scores, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [score2] == Dataloader.get(loader, Test, args, user1)
    end

    test "load has_many through many_to_many in second position", %{loader: loader} do
      leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
      user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()

      pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{url: "https://example.com/2.jpg"} |> Repo.insert!()

      %UserPicture{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()

      args = {:user_pictures, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, leaderboard)
        |> Dataloader.run()

      assert [pic1, pic2] == Dataloader.get(loader, Test, args, leaderboard)
    end

    test "load has_many through many_to_many in second position - with where on target schema and join_where on assoc schema",
         %{loader: loader} do
      leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
      user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()

      pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{url: "https://example.com/2.jpg", status: "published"} |> Repo.insert!()
      pic3 = %Picture{url: "https://example.com/3.jpg", status: "published"} |> Repo.insert!()

      %UserPicture{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic3.id, status: "published"} |> Repo.insert!()

      args = {:user_pictures_published, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, leaderboard)
        |> Dataloader.run()

      assert [pic3] == Dataloader.get(loader, Test, args, leaderboard)
    end

    test "load has_many through many_to_many in second position with third assoc", %{
      loader: loader
    } do
      leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
      user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()

      pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{url: "https://example.com/2.jpg"} |> Repo.insert!()

      %UserPicture{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()

      like1 = %Like{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      like2 = %Like{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()

      args = {:user_pictures_likes, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, leaderboard)
        |> Dataloader.run()

      assert [like1, like2] == Dataloader.get(loader, Test, args, leaderboard)
    end
  end
end
