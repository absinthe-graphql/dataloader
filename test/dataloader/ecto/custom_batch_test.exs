defmodule Dataloader.Ecto.CustomBatchTest do
  use ExUnit.Case, async: true

  alias Dataloader.{User, Post}
  import Ecto.Query
  alias Dataloader.TestRepo, as: Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    test_pid = self()

    source =
      Dataloader.Ecto.new(
        Repo,
        query: &query(&1, &2, test_pid),
        run_batch: &run_batch/5
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
  end

  defp query(queryable, _args, test_pid) do
    send(test_pid, :querying)
    queryable
  end

  # get the user by post title
  def run_batch(User, query, :post_title, titles, repo_opts) do
    query =
      from(
        u in query,
        join: p in assoc(u, :posts),
        where: p.title in ^titles,
        select: {p.title, u}
      )

    results =
      query
      |> Repo.all(repo_opts)
      |> Enum.group_by(fn {title, _} -> title end, fn {_, user} -> user end)

    for title <- titles, do: Map.get(results, title, [])
  end

  def run_batch(queryable, query, col, inputs, repo_opts) do
    Dataloader.Ecto.run_batch(Repo, queryable, query, col, inputs, repo_opts)
  end

  test "basic loading of one thing", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!()
    user2 = %User{username: "Ben Wilson"} |> Repo.insert!()

    rows = [
      %{user_id: user1.id, title: "foo"},
      %{user_id: user2.id, title: "baz"}
    ]

    _ = Repo.insert_all(Post, rows)

    titles = [
      [post_title: "baz"],
      [post_title: "foo"]
    ]

    loader =
      loader
      |> Dataloader.load_many(Test, {:one, User}, titles)
      |> Dataloader.run()

    assert [user2, user1] == Dataloader.get_many(loader, Test, {:one, User}, titles)
  end

  test "basic loading of many things", %{loader: loader} do
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
      |> Dataloader.load(Test, {:many, Post}, user_id: user1.id)
      |> Dataloader.load(Test, {:many, Post}, user_id: user2.id)
      |> Dataloader.run()

    assert [post1, post2] == Dataloader.get(loader, Test, {:many, Post}, user_id: user1.id)
    assert [post3] == Dataloader.get(loader, Test, {:many, Post}, user_id: user2.id)
  end
end
