defmodule Dataloader.KVTest do
  use ExUnit.Case, async: true

  @data [
    users: [
      [id: "ben", username: "Ben Wilson"],
      [id: "bruce", username: "Bruce Williams"],
    ]
  ]

  setup do

    test_pid = self()
    source = Dataloader.KV.new(&query(&1, &2, test_pid))

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Test, source)

    {:ok, loader: loader}
  end

  test "basic loading works", %{loader: loader} do

    user_ids = ~w(ben bruce)
    users = @data[:users]

    loader =
      loader
      |> Dataloader.load_many(Test, :users, user_ids)
      |> Dataloader.run

    loaded_users =
      loader
      |> Dataloader.get_many(Test, :users, user_ids)

    assert_received(:querying)

    assert length(loaded_users) == 2
    assert users == loaded_users

    # loading again doesn't query again due to caching
    loader
    |> Dataloader.load_many(Test, :users, user_ids)
    |> Dataloader.run

    refute_receive(:querying)
  end


  test "loading something from cache doesn't change the loader", %{loader: loader} do

    round1_loader =
      loader
      |> Dataloader.load(Test, :users, "ben")
      |> Dataloader.run

    assert ^round1_loader =
      round1_loader
      |> Dataloader.load(Test, :users, "ben")
      |> Dataloader.run

    assert loader != round1_loader
  end

  test "cache can be warmed", %{loader: loader} do

    loader = Dataloader.put(loader, Test, :users, "ben", @data[:users] |> List.first)

    loader
    |> Dataloader.load(Test, :users, "ben")
    |> Dataloader.run

    refute_receive(:querying)
  end

  test "pending_batches? is true when the cache is already warm", %{loader: loader} do
    loader = Dataloader.put(loader, Test, :users, "ben", @data[:users] |> List.first)

    loader = Dataloader.load(loader, Test, :users, "ben")
    assert Dataloader.pending_batches?(loader)

    Dataloader.run(loader)

    refute_receive(:querying)
  end

  defp query(batch_key, ids, test_pid) do
    send(test_pid, :querying)
    for item <- @data[batch_key], item[:id] in ids, into: %{} do
      {item[:id], item}
    end
  end
end
