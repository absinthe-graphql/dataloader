defmodule Dataloader.EctoTest do
  use ExUnit.Case, async: true

  alias Dataloader.{TestRepo, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)

    users = [
      %{username: "Ben Wilson"}
    ]
    TestRepo.insert_all(User, users)

    test_pid = self()
    source = Dataloader.Ecto.new(TestRepo, query: &query(&1, &2, test_pid))

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Test, source)

    {:ok, loader: loader}
  end

  test "basic loading works", %{loader: loader} do
    users = TestRepo.all(User)
    user_ids = users |> Enum.map(&(&1.id))

    loader =
      loader
      |> Dataloader.load_many(Test, User, user_ids)
      |> Dataloader.run

    loaded_users =
      loader
      |> Dataloader.get_many(Test, User, user_ids)

    assert_receive(:querying)

    assert length(loaded_users) == 1
    assert users == loaded_users

    # loading again doesn't query again due to caching
    loader
    |> Dataloader.load_many(Test, User, user_ids)
    |> Dataloader.run

    refute_receive(:querying)
  end

  test "association loading works" do

  end

  defp query(queryable, _args, test_pid) do
    send(test_pid, :querying)
    queryable
  end
end
