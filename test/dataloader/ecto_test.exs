defmodule Dataloader.EctoTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post, Like}
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

  defp query(Post, _, test_pid) do
    send(test_pid, :querying)

    Post
    |> where([p], is_nil(p.deleted_at))
    |> order_by(asc: :id)
  end

  defp query(queryable, _args, test_pid) do
    send(test_pid, :querying)
    queryable
  end

  test "basic loading works", %{loader: loader} do
    users = [
      %{username: "Ben Wilson"}
    ]

    Repo.insert_all(User, users)

    users = Repo.all(User)
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

  test "loading with cardinalty works", %{loader: loader} do
    user = %User{username: "Ben"} |> Repo.insert!()

    rows = [
      %{user_id: user.id, title: "foo"},
      %{user_id: user.id, title: "bar", deleted_at: DateTime.utc_now()}
    ]

    {_, [%{id: post_id} | _]} = Repo.insert_all(Post, rows, returning: [:id])

    loader =
      loader
      |> Dataloader.load(Test, {:one, Post}, id: post_id)
      |> Dataloader.load(Test, {:one, Post}, title: "bar")
      |> Dataloader.run()

    assert_receive(:querying)

    assert %Post{} = Dataloader.get(loader, Test, {:one, Post}, id: post_id)
    # this shouldn't be loaded because the `query` fun should filter it out,
    # because it's deleted
    refute Dataloader.get(loader, Test, {:one, Post}, title: "bar")
  end

  test "successive loads query only for new info", %{loader: loader} do
    [user1, user2] =
      [
        %User{username: "Ben Wilson"},
        %User{username: "Andy McVitty"}
      ]
      |> Enum.map(&Repo.insert!/1)

    [post1, post2] =
      [
        %Post{user_id: user1.id},
        %Post{user_id: user2.id}
      ]
      |> Enum.map(&Repo.insert!/1)

    loader =
      loader
      |> Dataloader.load(Test, :user, post1)
      |> Dataloader.run()

    loaded_user =
      loader
      |> Dataloader.get(Test, :user, post1)

    assert_receive(:querying)

    assert user1 == loaded_user

    loader =
      loader
      |> Dataloader.load(Test, :user, post1)
      |> Dataloader.load(Test, :user, post2)
      |> Dataloader.run()

    assert_receive(:querying)

    loaded_user1 =
      loader
      |> Dataloader.get(Test, :user, post1)

    loaded_user2 =
      loader
      |> Dataloader.get(Test, :user, post2)

    assert user2 == loaded_user2

    assert user1 == loaded_user1
  end

  test "association loading works", %{loader: loader} do
    user = %User{username: "Ben Wilson"} |> Repo.insert!()

    posts =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&Repo.insert!/1)

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
    user = %User{username: "Ben Wilson"} |> Repo.insert!()

    _ =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&Repo.insert!/1)

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
    user = %User{username: "Ben Wilson"} |> Repo.insert!()

    posts =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&Repo.insert!/1)

    loader = Dataloader.put(loader, Test, :posts, user, posts)

    loader
    |> Dataloader.load(Test, :posts, user)
    |> Dataloader.run()

    refute_receive(:querying)
  end

  test "%EctoAssociationNotLoaded{} struct doesn't warm cache", %{loader: loader} do
    user = %User{username: "Ben Wilson"} |> Repo.insert!()

    posts =
      [
        %Post{user_id: user.id},
        %Post{user_id: user.id}
      ]
      |> Enum.map(&Repo.insert!/1)

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

  test "we handle a variety of key possibilities", %{loader: loader} do
    assert Dataloader.load(loader, Test, {:one, User, %{foo: :bar}}, 1)
    # we accept too many things
    assert Dataloader.load(loader, Test, {User, %{foo: :bar}}, 1)
    assert Dataloader.load(loader, Test, {:one, User}, 1)

    %{message: message} =
      assert_raise(RuntimeError, fn ->
        Dataloader.load(loader, Test, {User, %{foo: :bar}}, username: 1)
      end)

    assert message =~ "cardinality"
  end

  test "works with has many through", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams"} |> Repo.insert!()

    post1 = %Post{user_id: user1.id} |> Repo.insert!()

    [
      %Like{user_id: user1.id, post_id: post1.id},
      %Like{user_id: user2.id, post_id: post1.id}
    ]
    |> Enum.map(&Repo.insert/1)

    loader =
      loader
      |> Dataloader.load(Test, :liking_users, post1)
      |> Dataloader.run()

    loaded_posts =
      loader
      |> Dataloader.get(Test, :liking_users, post1)

    assert length(loaded_posts) == 2
  end

  test "preloads aren't used", %{loader: loader} do
    user = %User{username: "Ben Wilson"} |> Repo.insert!()

    post =
      %Post{user_id: user.id}
      |> Repo.insert!()
      |> Repo.preload([:user])

    post = put_in(post.user.username, "foo")

    loaded_user =
      loader
      |> Dataloader.load(Test, :user, post)
      |> Dataloader.run()
      |> Dataloader.get(Test, :user, post)

    assert_receive(:querying)
    assert loaded_user.username != post.user.username
  end

  test "load same key multi times only adds to batches once", %{loader: loader} do
    loader_called_once = Dataloader.load(loader, Test, User, 1)
    loader_called_twice = Dataloader.load(loader_called_once, Test, User, 1)

    assert loader_called_once == loader_called_twice

    user = %User{username: "Ben Wilson"} |> Repo.insert!()

    loader_called_once = Dataloader.load(loader, Test, :posts, user)
    loader_called_twice = Dataloader.load(loader_called_once, Test, :posts, user)

    assert loader_called_once == loader_called_twice
  end
end
