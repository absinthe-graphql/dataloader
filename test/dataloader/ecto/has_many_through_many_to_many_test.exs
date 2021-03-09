defmodule Dataloader.Ecto.HasManyThroughManyToManyTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post, Score, Like}
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

  describe "has_many through mant-to-many associations" do
    test "load has_many through many_to_many", %{loader: loader} do
      leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
      user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id } |> Repo.insert!()

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
  end
end
