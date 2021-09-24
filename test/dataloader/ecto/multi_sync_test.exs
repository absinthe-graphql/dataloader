defmodule Dataloader.Ecto.MultiSyncTest do
  use ExUnit.Case, async: false

  alias Dataloader.User
  alias Dataloader.TestRepo, as: Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok = Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

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

  defp query(schema, _params, test_pid) do
    send(test_pid, :querying)

    schema
  end

  test "loads data", %{loader: loader} do
    user =
      %User{username: "Ben Wilson"}
      |> Repo.insert!()

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:loader, fn _, _ ->
        loader =
          loader
          |> Dataloader.load(Test, User, user.id)
          |> Dataloader.run()

        {:ok, loader}
      end)
      |> Repo.transaction()

    assert {:ok, %{loader: loader}} = result
    assert user == Dataloader.get(loader, Test, User, user.id)
  end
end
