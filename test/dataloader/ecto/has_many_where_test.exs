defmodule Dataloader.Ecto.HasManyWhereTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post}
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

  describe "where in has-many associations" do
    test "compare value", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      post1 = %Post{user_id: user1.id, title: "foo", status: "published"} |> Repo.insert!()
      _post2 = %Post{user_id: user1.id, title: "bar", status: "unpublished"} |> Repo.insert!()

      args = {:published_posts, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [post1] == Dataloader.get(loader, Test, args, user1)
    end
  end
end
