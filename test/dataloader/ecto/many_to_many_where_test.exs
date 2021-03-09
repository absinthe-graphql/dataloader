defmodule Dataloader.Ecto.ManyToManyWhereTest do
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

  describe "where in mant-to-many associations" do
    test "compare value", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{status: "published", url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{status: "unpublished", url: "https://example.com/2.jpg"} |> Repo.insert!()

      %UserPicture{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()

      args = {:pictures_compare_value, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic1] == Dataloader.get(loader, Test, args, user1)
    end

    test "is nil", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{status: "published", url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{status: nil, url: "https://example.com/2.jpg"} |> Repo.insert!()

      %UserPicture{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()

      args = {:pictures_nil, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic2] == Dataloader.get(loader, Test, args, user1)
    end

    test "in list", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{status: "one", url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{status: "published", url: "https://example.com/2.jpg"} |> Repo.insert!()
      pic3 = %Picture{status: "blurry", url: "https://example.com/3.jpg"} |> Repo.insert!()

      %UserPicture{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic3.id} |> Repo.insert!()

      args = {:pictures_in, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic2, pic3] == Dataloader.get(loader, Test, args, user1)
    end

    test "fragment", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

      pic1 = %Picture{status: "pub", url: "https://example.com/1.jpg"} |> Repo.insert!()
      pic2 = %Picture{status: "unpub", url: "https://example.com/2.jpg"} |> Repo.insert!()
      pic3 = %Picture{status: "pub", url: "https://example.com/3.jpg"} |> Repo.insert!()

      %UserPicture{user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()
      %UserPicture{user_id: user1.id, picture_id: pic3.id} |> Repo.insert!()

      args = {:pictures_fragment, %{limit: 10}}

      loader =
        loader
        |> Dataloader.load(Test, args, user1)
        |> Dataloader.run()

      assert [pic2] == Dataloader.get(loader, Test, args, user1)
    end
  end
end
