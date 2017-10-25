defmodule Dataloader.EctoTest do
  use ExUnit.Case, async: true

  alias Dataloader.{TestRepo, User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)

    users = [
      %{username: "Ben Wilson"}
    ]
    TestRepo.insert_all(User, users)

    source = Dataloader.Ecto.new(TestRepo)

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Test, source)

    {:ok, loader: loader}
  end

  test "basic loading works", %{loader: loader} do
    users = TestRepo.all(User)
    user_ids = users |> Enum.map(&(&1.id))

    loaded_users =
      loader
      |> Dataloader.load_many(Test, User, user_ids)
      |> Dataloader.run
      |> Dataloader.get_many(Test, User, user_ids)

    assert length(loaded_users) == 1
    assert users == loaded_users
  end

  test "association loading works" do

  end
end
