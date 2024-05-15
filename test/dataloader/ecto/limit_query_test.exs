defmodule Dataloader.LimitQueryTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post, Like, Score}
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

  defp query(Post, %{limit: limit, order_by: order_by, min_likes: n}, test_pid) do
    send(test_pid, :querying)

    Post
    |> from(as: :post)
    |> join(:inner, [post: p], l in assoc(p, :likes), as: :like)
    |> group_by([post: p], p.id)
    |> having(count() >= ^n)
    |> order_by(^order_by)
    |> limit(^limit)
    |> preload(likes: :user)
  end

  defp query(schema, %{limit: limit, order_by: order_by}, test_pid) do
    send(test_pid, :querying)

    schema
    |> order_by(^order_by)
    |> limit(^limit)
  end

  defp query(schema, %{limit: limit, distinct: true, order_by: order_by}, test_pid) do
    send(test_pid, :querying)

    schema
    |> order_by(^order_by)
    |> limit(^limit)
    |> distinct(true)
  end

  test "Query limit does not apply globally", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams"} |> Repo.insert!()

    [post1, _post2, post3, _post4] =
      [
        %Post{user_id: user1.id, title: "foo"},
        %Post{user_id: user1.id, title: "baz"},
        %Post{user_id: user2.id, title: "bar"},
        %Post{user_id: user2.id, title: "qux"}
      ]
      |> Enum.map(&Repo.insert!/1)

    args = {{:many, Post}, %{limit: 1, order_by: [asc: :id]}}

    loader =
      loader
      |> Dataloader.load(Test, args, user_id: user1.id)
      |> Dataloader.load(Test, args, user_id: user2.id)
      |> Dataloader.run()

    assert [post1] == Dataloader.get(loader, Test, args, user_id: user1.id)
    assert [post3] == Dataloader.get(loader, Test, args, user_id: user2.id)
  end

  test "Query limit without filters", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams"} |> Repo.insert!()

    [post1, post2, _post3, _post4] =
      [
        %Post{user_id: user1.id, title: "foo"},
        %Post{user_id: user1.id, title: "baz"},
        %Post{user_id: user2.id, title: "bar"},
        %Post{user_id: user2.id, title: "qux"}
      ]
      |> Enum.map(&Repo.insert!/1)

    args0 = {{:one, Post}, %{limit: 1, order_by: [asc: :id]}}
    args1 = {{:many, Post}, %{limit: 1, order_by: [asc: :id]}}
    args2 = {{:many, Post}, %{limit: 2, order_by: [asc: :id]}}

    loader =
      loader
      |> Dataloader.load(Test, args0, [])
      |> Dataloader.load(Test, args1, [])
      |> Dataloader.load(Test, args2, [])
      |> Dataloader.run()

    assert post1 == Dataloader.get(loader, Test, args0, [])
    assert [post1] == Dataloader.get(loader, Test, args1, [])
    assert [post1, post2] == Dataloader.get(loader, Test, args2, [])
  end

  test "Load has-many association with limit", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams"} |> Repo.insert!()

    [_post1, post2, post3, _post4] =
      [
        %Post{user_id: user1.id, title: "foo"},
        %Post{user_id: user1.id, title: "baz"},
        %Post{user_id: user2.id, title: "bar"},
        %Post{user_id: user2.id, title: "qux"}
      ]
      |> Enum.map(&Repo.insert!/1)

    args = {:posts, %{limit: 1, order_by: [asc: :title]}}

    loader =
      loader
      |> Dataloader.load_many(Test, args, [user1, user2])
      |> Dataloader.run()

    assert [post2] == Dataloader.get(loader, Test, args, user1)
    assert [post3] == Dataloader.get(loader, Test, args, user2)
  end

  test "Load has-many-through association with limit", %{loader: loader} do
    leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
    user1 = %User{username: "Ben Wilson", leaderboard: leaderboard} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams", leaderboard: leaderboard} |> Repo.insert!()

    posts =
      [
        %Post{user_id: user1.id, title: "foo"},
        %Post{user_id: user1.id, title: "baz"},
        %Post{user_id: user2.id, title: "bar"},
        %Post{user_id: user2.id, title: "qux"}
      ]
      |> Enum.map(&Repo.insert!/1)

    [_score1, score2, _score3, score4] =
      Enum.map(posts, fn post ->
        %Score{post_id: post.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
      end)

    args = {:scores, %{limit: 1, order_by: [desc: :post_id]}}

    loader =
      loader
      |> Dataloader.load_many(Test, args, [user1, user2])
      |> Dataloader.run()

    assert [score2] == Dataloader.get(loader, Test, args, user1)
    assert [score4] == Dataloader.get(loader, Test, args, user2)
  end

  test "Loads distinct has-many association with limit", %{loader: loader} do
    leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
    user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams", leaderboard_id: leaderboard.id} |> Repo.insert!()
    user3 = %User{username: "Chris McCord"} |> Repo.insert!()
    user4 = %User{username: "Jose Valim"} |> Repo.insert!()

    post1 = %Post{user_id: user1.id, title: "foo"} |> Repo.insert!()
    post2 = %Post{user_id: user1.id, title: "bar"} |> Repo.insert!()
    post3 = %Post{user_id: user2.id, title: "baz"} |> Repo.insert!()
    post4 = %Post{user_id: user2.id, title: "qux"} |> Repo.insert!()

    _score1 = %Score{post_id: post1.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
    _score2 = %Score{post_id: post2.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
    _score3 = %Score{post_id: post3.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
    _score4 = %Score{post_id: post4.id, leaderboard_id: leaderboard.id} |> Repo.insert!()

    Enum.each([user2, user3, user4], fn user -> Repo.insert!(%Like{user: user, post: post1}) end)
    Enum.each([user3, user4], fn user -> Repo.insert!(%Like{user: user, post: post2}) end)
    Enum.each([user1, user3, user4], fn user -> Repo.insert!(%Like{user: user, post: post3}) end)
    Enum.each([user1, user4], fn user -> Repo.insert!(%Like{user: user, post: post4}) end)

    args = {:fans, %{limit: 3, order_by: [asc: :username]}}

    loader =
      loader
      |> Dataloader.load_many(Test, args, [user1, user2])
      |> Dataloader.run()

    assert [%{username: "Bruce Williams"}, %{username: "Chris McCord"}, %{username: "Jose Valim"}] =
             Dataloader.get(loader, Test, args, user1)

    assert [%{username: "Ben Wilson"}, %{username: "Chris McCord"}, %{username: "Jose Valim"}] =
             Dataloader.get(loader, Test, args, user2)
  end

  test "Loads has-many association with limit and pre-existing distinct", %{loader: loader} do
    leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
    user1 = %User{username: "Ben Wilson", leaderboard_id: leaderboard.id} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams", leaderboard_id: leaderboard.id} |> Repo.insert!()
    user3 = %User{username: "Chris McCord"} |> Repo.insert!()
    user4 = %User{username: "Jose Valim"} |> Repo.insert!()

    post1 = %Post{user_id: user1.id, title: "foo"} |> Repo.insert!()
    post2 = %Post{user_id: user1.id, title: "bar"} |> Repo.insert!()
    post3 = %Post{user_id: user2.id, title: "baz"} |> Repo.insert!()
    post4 = %Post{user_id: user2.id, title: "qux"} |> Repo.insert!()

    _score1 = %Score{post_id: post1.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
    _score2 = %Score{post_id: post2.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
    _score3 = %Score{post_id: post3.id, leaderboard_id: leaderboard.id} |> Repo.insert!()
    _score4 = %Score{post_id: post4.id, leaderboard_id: leaderboard.id} |> Repo.insert!()

    Enum.each([user2, user3, user4], fn user -> Repo.insert!(%Like{user: user, post: post1}) end)
    Enum.each([user3, user4], fn user -> Repo.insert!(%Like{user: user, post: post2}) end)
    Enum.each([user1, user3, user4], fn user -> Repo.insert!(%Like{user: user, post: post3}) end)
    Enum.each([user1, user4], fn user -> Repo.insert!(%Like{user: user, post: post4}) end)

    args = {:fans, %{distinct: true, limit: 3, order_by: [asc: :username]}}

    loader =
      loader
      |> Dataloader.load_many(Test, args, [user1, user2])
      |> Dataloader.run()

    assert [%{username: "Bruce Williams"}, %{username: "Chris McCord"}, %{username: "Jose Valim"}] =
             Dataloader.get(loader, Test, args, user1)

    assert [%{username: "Ben Wilson"}, %{username: "Chris McCord"}, %{username: "Jose Valim"}] =
             Dataloader.get(loader, Test, args, user2)
  end

  test "Load many-to-many association with limit", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams"} |> Repo.insert!()
    user3 = %User{username: "Chris McCord"} |> Repo.insert!()
    user4 = %User{username: "Jose Valim"} |> Repo.insert!()

    [post1, post2, post3, post4] =
      [
        %Post{user_id: user1.id, title: "foo"},
        %Post{user_id: user1.id, title: "baz"},
        %Post{user_id: user2.id, title: "bar"},
        %Post{user_id: user2.id, title: "qux"}
      ]
      |> Enum.map(&Repo.insert!/1)

    %Like{user_id: user3.id, post_id: post1.id} |> Repo.insert!()
    %Like{user_id: user3.id, post_id: post3.id} |> Repo.insert!()
    %Like{user_id: user4.id, post_id: post2.id} |> Repo.insert!()
    %Like{user_id: user4.id, post_id: post4.id} |> Repo.insert!()

    args = {:liked_posts, %{limit: 1, order_by: [desc: :title]}}

    loader =
      loader
      |> Dataloader.load_many(Test, args, [user3, user4])
      |> Dataloader.run()

    assert [post1] == Dataloader.get(loader, Test, args, user3)
    assert [post4] == Dataloader.get(loader, Test, args, user4)
  end

  test "Loads association when query contains joins", %{loader: loader} do
    leaderboard = %Dataloader.Leaderboard{name: "Top Bloggers"} |> Repo.insert!()
    user1 = %User{username: "Ben Wilson", leaderboard: leaderboard} |> Repo.insert!()
    user2 = %User{username: "Bruce Williams", leaderboard: leaderboard} |> Repo.insert!()

    _post1 = %Post{user_id: user1.id, title: "foo"} |> Repo.insert!()
    post2 = %Post{user_id: user1.id, title: "bar"} |> Repo.insert!()
    post3 = %Post{user_id: user2.id, title: "baz"} |> Repo.insert!()
    _post4 = %Post{user_id: user2.id, title: "qux"} |> Repo.insert!()

    %Like{user_id: user2.id, post_id: post2.id} |> Repo.insert!()
    %Like{user_id: user1.id, post_id: post3.id} |> Repo.insert!()

    %Score{post: post2, leaderboard: leaderboard} |> Repo.insert!()
    %Score{post: post3, leaderboard: leaderboard} |> Repo.insert!()

    args = {:awarded_posts, %{limit: 1, order_by: [asc: :title], min_likes: 1}}

    loader =
      loader
      |> Dataloader.load_many(Test, args, [user1, user2])
      |> Dataloader.run()

    assert [p1 = %{title: "bar"}] = Dataloader.get(loader, Test, args, user1)
    assert [p2 = %{title: "baz"}] = Dataloader.get(loader, Test, args, user2)
    assert [%{user: %{username: "Bruce Williams"}}] = p1.likes
    assert [%{user: %{username: "Ben Wilson"}}] = p2.likes
  end
end
