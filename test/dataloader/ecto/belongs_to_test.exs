defmodule Dataloader.Ecto.BelongsToTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post, Like, Country, Address}
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

  defp query(queryable, _args, test_pid) do
    send(test_pid, :querying)
    queryable
  end

  describe "where in belongs_to association" do
    test "returns entity when where clause matches", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      post1 = %Post{user_id: user1.id, title: "foo", status: "published"} |> Repo.insert!()

      like1 = %Like{user_id: user1.id, post_id: post1.id} |> Repo.insert!()

      args = {:post, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, like1)
        |> Dataloader.run()

      assert post1 == Dataloader.get(loader, Test, args, like1)
    end

    test "returns nil when where clause doesn't match", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      post1 = %Post{user_id: user1.id, title: "foo", status: "unpublished"} |> Repo.insert!()

      like1 = %Like{user_id: user1.id, post_id: post1.id} |> Repo.insert!()

      args = {:post, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, like1)
        |> Dataloader.run()

      assert nil == Dataloader.get(loader, Test, args, like1)
    end
  end

  test "belongs_to is inside the embedded schema", %{loader: loader} do
    country1 = %Country{name: "USA"} |> Repo.insert!()
    country2 = %Country{name: "Canada"} |> Repo.insert!()

    address1 = %Address{city: "New York", country_id: country1.id}
    address2 = %Address{city: "Toronto", country_id: country2.id}
    address3 = %Address{city: "Washington"}

    args = {:country, %{}}

    loader =
      loader
      |> Dataloader.load(Test, args, address1)
      |> Dataloader.load(Test, args, address2)
      |> Dataloader.load(Test, args, address3)
      |> Dataloader.run()

    assert country1 == Dataloader.get(loader, Test, args, address1)
    assert country2 == Dataloader.get(loader, Test, args, address2)
    assert nil == Dataloader.get(loader, Test, args, address3)
  end
end
