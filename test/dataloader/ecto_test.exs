defmodule Dataloader.EctoTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post, Like, Score, Leaderboard}
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

  defp query(User, args, test_pid) do
    {sort_order, args} = Map.pop(args, :sort_order)
    {sort_by, args} = Map.pop(args, :sort_by)
    send(test_pid, :querying)

    User
    |> where(^Enum.to_list(args))
    |> (fn user ->
          if is_nil(sort_by) or is_nil(sort_order) do
            user
          else
            order_by(user, {^sort_order, ^sort_by})
          end
        end).()
  end

  defp query(queryable, _args, test_pid) do
    send(test_pid, :querying)
    queryable
  end

  test "basic loading works along with telemetry metrics", %{loader: loader, test: test} do
    self = self()

    :ok =
      :telemetry.attach_many(
        "#{__MODULE__}_#{test}",
        [
          [:dataloader, :source, :batch, :run, :start],
          [:dataloader, :source, :batch, :run, :stop]
        ],
        fn name, measurements, metadata, _ ->
          send(self, {:telemetry_event, name, measurements, metadata})
        end,
        nil
      )

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

    assert_receive {:telemetry_event, [:dataloader, :source, :batch, :run, :start],
                    %{system_time: _}, %{id: _, batch: _}}

    assert_receive {:telemetry_event, [:dataloader, :source, :batch, :run, :stop], %{duration: _},
                    %{id: _, batch: _}}

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
      %{
        user_id: user.id,
        title: "bar",
        deleted_at: DateTime.truncate(DateTime.utc_now(), :second)
      }
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

  test "loading directly with string for id column works", %{loader: loader} do
    user = %User{username: "Ben"} |> Repo.insert!()

    user_id_string = Integer.to_string(user.id)

    loader =
      loader
      |> Dataloader.load(Test, User, user_id_string)
      |> Dataloader.run()

    assert_receive(:querying)

    assert Repo.get(User, user_id_string) == Dataloader.get(loader, Test, User, user_id_string)
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

    assert message =~ "Cardinality"
  end

  test "basic loading of all things", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams"} |> Repo.insert!()

    [post1, post2, post3] =
      [
        %Post{user_id: user1.id, title: "foo"},
        %Post{user_id: user1.id, title: "baz"},
        %Post{user_id: user2.id, title: "bar"}
      ]
      |> Enum.map(&Repo.insert!/1)

    loader =
      loader
      |> Dataloader.load(Test, {:many, Post}, [])
      |> Dataloader.run()

    assert [post1, post2, post3] == Dataloader.get(loader, Test, {:many, Post}, [])
  end

  describe "has_many through:" do
    test "basic loading works", %{loader: loader} do
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

    test "order_by works", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
      user2 = %User{username: "Bruce Williams"} |> Repo.insert!()

      post1 = %Post{user_id: user1.id} |> Repo.insert!()

      [
        %Like{user_id: user1.id, post_id: post1.id},
        %Like{user_id: user2.id, post_id: post1.id}
      ]
      |> Enum.map(&Repo.insert/1)

      for {sort_order, expected_usernames} <- [
            {:asc, ["Ben Wilson", "Bruce Williams"]},
            {:desc, ["Bruce Williams", "Ben Wilson"]}
          ] do
        loader =
          loader
          |> Dataloader.load(
            Test,
            {:liking_users, [sort_order: sort_order, sort_by: :username]},
            post1
          )
          |> Dataloader.run()

        loaded_posts =
          loader
          |> Dataloader.get(
            Test,
            {:liking_users, [sort_order: sort_order, sort_by: :username]},
            post1
          )

        ordered_usernames = Enum.map(loaded_posts, & &1.username)

        assert ordered_usernames == expected_usernames,
               "got #{inspect(ordered_usernames)} but was expecting #{inspect(expected_usernames)} for sort_order #{sort_order}"
      end
    end

    test "works with query filtering", %{loader: loader} do
      user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
      user2 = %User{username: "Bruce Williams"} |> Repo.insert!()

      post1 = %Post{user_id: user1.id} |> Repo.insert!()

      [
        %Like{user_id: user1.id, post_id: post1.id},
        %Like{user_id: user2.id, post_id: post1.id}
      ]
      |> Enum.map(&Repo.insert/1)

      key = {:liking_users, %{username: "Ben Wilson"}}

      loader =
        loader
        |> Dataloader.load(Test, key, post1)
        |> Dataloader.run()

      loaded_posts =
        loader
        |> Dataloader.get(Test, key, post1)

      assert length(loaded_posts) == 1
    end

    test "works when nested", %{loader: loader} do
      leaderboard = %Leaderboard{name: "Bestliked"} |> Repo.insert!()
      user = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()

      post = %Post{user_id: user.id} |> Repo.insert!()
      _score = %Score{post_id: post.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
      _like1 = %Like{post_id: post.id, user_id: user.id} |> Repo.insert!()
      _like2 = %Like{post_id: post.id, user_id: user.id} |> Repo.insert!()

      loader =
        loader
        |> Dataloader.load(Test, :awarded_posts, user)
        |> Dataloader.load(Test, :likes, user)
        |> Dataloader.run()

      loaded_posts =
        loader
        |> Dataloader.get(Test, :awarded_posts, user)

      loaded_likes =
        loader
        |> Dataloader.get(Test, :likes, user)

      assert length(loaded_posts) == 1
      assert length(loaded_likes) == 2
    end
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

  test "when the query fails to find a record it raises an error", %{loader: loader} do
    assert_raise Dataloader.GetError, ~r/Unable to find batch/, fn ->
      Dataloader.get(loader, Test, User, "doesn't exist")
    end
  end

  test "when the parent is not a struct it raises an error", %{loader: loader} do
    assert_raise Dataloader.GetError, ~r/:posts.*Ecto struct/s, fn ->
      {:ok, user} = Repo.insert(%User{username: "Devon Estes"})

      loader
      |> Dataloader.load(Test, :posts, Map.from_struct(user))
      |> Dataloader.run()
    end
  end

  test "when dataloader times out it raises an error" do
    user =
      %User{username: "Ben Wilson"}
      |> Repo.insert!()

    source =
      Dataloader.Ecto.new(
        Repo,
        timeout: 1,
        query: fn queryable, _ ->
          :timer.sleep(5)
          queryable
        end
      )

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Timeout, source)

    loader =
      loader
      |> Dataloader.load(Timeout, User, user.id)
      |> Dataloader.run()

    assert_raise Dataloader.GetError, ~r/:timeout/, fn ->
      Dataloader.get(loader, Timeout, User, user.id)
    end
  end

  test "when there are many batches (more than 32)" do
    source =
      Dataloader.Ecto.new(
        Repo,
        query: fn queryable, _ ->
          queryable
        end
      )

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Test, source)

    users =
      for x <- 0..50 do
        %User{username: "Ben Wilson #{x}"} |> Repo.insert!()
      end

    loader =
      users
      |> Enum.reduce(loader, fn user, loader ->
        # Force a batch per user by adding id to batch key
        Dataloader.load(loader, Test, {User, id: user.id}, user.id)
      end)
      |> Dataloader.run()

    assert Enum.map(users, &Dataloader.get(loader, Test, {User, id: &1.id}, &1.id)) ==
             users
  end

  test "run inside transaction" do
    user = %User{username: "Ben Wilson"} |> Repo.insert!()

    source = Dataloader.Ecto.new(Repo, async: false)

    loader =
      Dataloader.new(async: false)
      |> Dataloader.add_source(Test, source)

    Dataloader.load(loader, Test, User, user.id)

    Repo.transaction(fn ->
      loader =
        loader
        |> Dataloader.load(Test, User, user.id)
        |> Dataloader.run()

      loaded =
        loader
        |> Dataloader.get(Test, User, user.id)

      assert ^user = loaded
    end)
  end
end
