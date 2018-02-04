defmodule Dataloader.EctoTest do
  use ExUnit.Case, async: true

  alias Dataloader.{TestRepo, User, Post}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)

    test_pid = self()
    source = Dataloader.Ecto.new(TestRepo, query: &query(&1, &2, test_pid))

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Test, source)

    {:ok, loader: loader}
  end

  test "basic loading works", %{loader: loader} do
    users = [
      %{username: "Ben Wilson"}
    ]

    TestRepo.insert_all(User, users)

    users = TestRepo.all(User)
    user_ids = users |> Enum.map(& &1.id)

    loader =
      loader
      |> Dataloader.load_many(Test, User, user_ids)
      |> Dataloader.run()

    loaded_users =
      loader
      |> Dataloader.get_many(Test, User, user_ids)

    assert_receive(:querying)

    assert length(loaded_users) == 1
    assert users == loaded_users

    # loading again doesn't query again due to caching
    loader
    |> Dataloader.load_many(Test, User, user_ids)
    |> Dataloader.run()

    refute_receive(:querying)
  end
  
  test "successive loads query only for new info", %{loader: loader} do
    users = [
      %{username: "Ben Wilson"},
      %{username: "Andy McVitty"},
    ]

    TestRepo.insert_all(User, users)

    [user1, user2] = TestRepo.all(User)

    loader =
      loader
      |> Dataloader.load(Test, User, user1.id)
      |> Dataloader.run()

    loaded_user =
      loader
      |> Dataloader.get(Test, User, user1.id)

    assert_receive(:querying)

    assert user1 == loaded_user

    # loading both users queries again (only for second user (confirmed from log))
    loader =
      loader
      |> Dataloader.load(Test, User, user1.id)
      |> Dataloader.load(Test, User, user2.id)
      |> Dataloader.run()
    assert_receive(:querying)

    # And we should now be able to get both user1 and user2 from the cache
    # (However, this is the odd behavior - we can't get user1 any more!)
    loaded_user1 =
      loader
      |> Dataloader.get(Test, User, user1.id)

    loaded_user2 =
      loader
      |> Dataloader.get(Test, User, user2.id)

    assert user2 == loaded_user2
    
    # This assert fails; loaded_user 1 is nil
    assert user1 == loaded_user1
  end

  test "association loading works", %{loader: loader} do
    user = %User{username: "Ben Wilson"} |> TestRepo.insert!()

    posts =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&TestRepo.insert!/1)

    loader =
      loader
      |> Dataloader.load(Test, :posts, user)
      |> Dataloader.run()

    loaded_posts =
      loader
      |> Dataloader.get(Test, :posts, user)

    assert posts == loaded_posts
    assert_receive(:querying)

    # loading again doesn't query again due to caching
    loader
    |> Dataloader.load(Test, :posts, user)
    |> Dataloader.run()

    refute_receive(:querying)
  end

  test "loading something from cache doesn't change the loader", %{loader: loader} do
    user = %User{username: "Ben Wilson"} |> TestRepo.insert!()

    _ =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&TestRepo.insert!/1)

    round1_loader =
      loader
      |> Dataloader.load(Test, :posts, user)
      |> Dataloader.run()

    assert ^round1_loader =
             round1_loader
             |> Dataloader.load(Test, :posts, user)
             |> Dataloader.run()

    assert loader != round1_loader
  end

  test "cache can be warmed", %{loader: loader} do
    user = %User{username: "Ben Wilson"} |> TestRepo.insert!()

    posts =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&TestRepo.insert!/1)

    loader = Dataloader.put(loader, Test, :posts, user, posts)

    loader
    |> Dataloader.load(Test, :posts, user)
    |> Dataloader.run()

    refute_receive(:querying)
  end

  test "ecto not association loaded struct doesn't warm cache", %{loader: loader} do
    user = %User{username: "Ben Wilson"} |> TestRepo.insert!()

    posts =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&TestRepo.insert!/1)

    loader = Dataloader.put(loader, Test, :posts, user, user.posts)

    loader =
      loader
      |> Dataloader.load(Test, :posts, user)
      |> Dataloader.run()

    loaded_posts =
      loader
      |> Dataloader.get(Test, :posts, user)

    assert posts == loaded_posts
    assert_receive(:querying)
  end

  defp query(queryable, _args, test_pid) do
    send(test_pid, :querying)
    queryable
  end
end
