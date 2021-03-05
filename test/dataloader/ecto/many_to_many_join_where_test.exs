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

  defp query(User, %{limit: limit}, test_pid) do
    send(test_pid, :querying)

    User
    |> from(as: :user)
    |> limit(^limit)
  end

  defp query(schema, %{limit: limit}, test_pid) do
    send(test_pid, :querying)

    schema
    |> limit(^limit)
  end

  test ":join_where is filtering associated entities", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()

    pic1 = %Picture{url: "https://example.com/1.jpg"} |> Repo.insert!()
    pic2 = %Picture{url: "https://example.com/2.jpg"} |> Repo.insert!()
    pic3 = %Picture{url: "https://example.com/3.jpg"} |> Repo.insert!()


    %UserPicture{status: "published", user_id: user1.id, picture_id: pic1.id} |> Repo.insert!()
    %UserPicture{status: "published", user_id: user1.id, picture_id: pic2.id} |> Repo.insert!()
    %UserPicture{status: "unpublished", user_id: user1.id, picture_id: pic3.id} |> Repo.insert!()

    args = {:pictures, %{limit: 10}}

    loader =
      loader
      |> Dataloader.load(Test, args, user1)
      |> Dataloader.run()

    assert [pic1, pic2] == Dataloader.get(loader, Test, args, user1)
  end
end
