defmodule Dataloader.Ecto.ManyToManyJoinWhereTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Picture, UserPicture}
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

  describe "join_where in many-to-many associations" do
    test "compare value", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{url: "https://example.com/2.jpg"} |> Repo.insert!()

      %UserPicture{status: "published", user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()

      %UserPicture{status: "unpublished", user_id: user1.id, picture_id: pic2.id}
      |> Repo.insert!()

      args = {:pictures_join_compare_value, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic1] == Dataloader.get(loader, Test, args, user1)
    end

    test "is nil", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{url: "https://example.com/2.jpg"} |> Repo.insert!()

      %UserPicture{status: nil, user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()

      %UserPicture{status: "unpublished", user_id: user1.id, picture_id: pic2.id}
      |> Repo.insert!()

      args = {:pictures_join_nil, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic1] == Dataloader.get(loader, Test, args, user1)
    end

    test "in list", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{url: "https://example.com/2.jpg"} |> Repo.insert!()
      pic3 = %Picture{url: "https://example.com/3.jpg"} |> Repo.insert!()

      %UserPicture{status: "published", user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()

      %UserPicture{status: "unpublished", user_id: user1.id, picture_id: pic2.id}
      |> Repo.insert!()

      %UserPicture{status: "blurry", user_id: user1.id, picture_id: pic3.id}
      |> Repo.insert!()

      args = {:pictures_join_in, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic1, pic3] == Dataloader.get(loader, Test, args, user1)
    end

    test "fragment", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{url: "https://example.com/2.jpg"} |> Repo.insert!()
      pic3 = %Picture{url: "https://example.com/3.jpg"} |> Repo.insert!()

      %UserPicture{status: "pub", user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{status: "unpub", user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()
      %UserPicture{status: "pub", user_id: user1.id, picture_id: pic3.id} |> Repo.insert!()

      args = {:pictures_join_fragment, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic2] == Dataloader.get(loader, Test, args, user1)
    end
  end
end
