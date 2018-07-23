defmodule Dataloader.KVTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  @data [
    users: [
      [id: "ben", username: "Ben Wilson"],
      [id: "bruce", username: "Bruce Williams"]
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
      |> Dataloader.run()

    loaded_users =
      loader
      |> Dataloader.get_many(Test, :users, user_ids)

    assert_received(:querying)

    assert length(loaded_users) == 2
    assert users == loaded_users

    # loading again doesn't query again due to caching
    loader
    |> Dataloader.load_many(Test, :users, user_ids)
    |> Dataloader.run()

    refute_receive(:querying)
  end

  test "loading something from cache doesn't change the loader", %{loader: loader} do
    round1_loader =
      loader
      |> Dataloader.load(Test, :users, "ben")
      |> Dataloader.run()

    assert ^round1_loader =
             round1_loader
             |> Dataloader.load(Test, :users, "ben")
             |> Dataloader.run()

    assert loader != round1_loader
  end

  test "cache can be warmed", %{loader: loader} do
    loader = Dataloader.put(loader, Test, :users, "ben", @data[:users] |> List.first())

    loader
    |> Dataloader.load(Test, :users, "ben")
    |> Dataloader.run()

    refute_receive(:querying)
  end

  test "raises with when fetching values that failed to load", %{loader: loader} do
    user_ids = ~w(ben bruce something_that_errors)

    log =
      capture_log(fn ->
        loader =
          loader
          |> Dataloader.load_many(Test, :users, user_ids)
          |> Dataloader.run()

        assert_raise Dataloader.GetError,
                     ~r/Failed when fetching key 'something_that_errors'/,
                     fn ->
                       loader
                       |> Dataloader.get(Test, :users, "something_that_errors")
                     end

        assert_raise Dataloader.GetError,
                     ~r/Failed when fetching key 'something_that_errors'/,
                     fn ->
                       loader
                       |> Dataloader.get_many(Test, :users, ~w(something_that_errors))
                     end

        assert_raise Dataloader.GetError,
                     ~r/Failed when fetching key 'something_that_errors'/,
                     fn ->
                       loader
                       |> Dataloader.get_many(Test, :users, user_ids)
                     end
      end)

    assert log =~ "Failed when fetching key 'something_that_errors'"
  end

  test "batches that succeed can still return data if there are failures in other batches", %{
    loader: loader
  } do
    user_ids = ~w(ben bruce)

    log =
      capture_log(fn ->
        loader =
          loader
          |> Dataloader.load_many(Test, :users, user_ids)
          |> Dataloader.load(Test, :books, "something_that_errors")
          |> Dataloader.run()

        loaded_users =
          loader
          |> Dataloader.get_many(Test, :users, user_ids)

        assert @data[:users] == loaded_users

        assert_raise Dataloader.GetError,
                     ~r/Failed when fetching key 'something_that_errors'/,
                     fn ->
                       loader
                       |> Dataloader.get(Test, :books, "something_that_errors")
                     end
      end)

    assert log =~ "Failed when fetching key 'something_that_errors'"
  end

  test "raises default error if not loaded yet", %{loader: loader} do
    assert_raise Dataloader.GetError, ~r/Unable to find batch :users/, fn ->
      loader
      |> Dataloader.get(Test, :users, "doesn't exist")
    end
  end

  test "returns nil for a key if we've loaded it but it can't be found", %{loader: loader} do
    not_found_users =
      loader
      |> Dataloader.load(Test, :users, "not_found")
      |> Dataloader.run()
      |> Dataloader.get_many(Test, :users, ~w(not_found))

    assert not_found_users == [nil]
  end

  defp query(batch_key, ids, test_pid) do
    send(test_pid, :querying)

    for id <- ids, into: %{} do
      query(batch_key, id)
    end
  end

  defp query(_batch_key, "something_that_errors"),
    do: raise("Failed when fetching key 'something_that_errors'")

  defp query(batch_key, id) do
    item =
      @data[batch_key]
      |> Enum.find(fn data -> data[:id] == id end)

    {id, item}
  end
end
