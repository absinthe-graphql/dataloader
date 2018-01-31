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
        [
          query: &query(&1, &2, test_pid),
          run_batch: &run_batch/4
      ]

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

  def run_batch(User, query, {:post_title, titles}, repo_opts) do
    query = from u in query,
      join: p in assoc(u, :posts),
      where: p.title in ^titles,
      select: {p.title, u}

    results =
      query
      |> Repo.all(repo_opts)
      |> Map.new
    for title <- titles, do: Map.get(results, title)
  end

  test "basic loading of one thing", %{loader: loader} do
    user1 = %User{username: "Ben Wilson"} |> Repo.insert!
    user2 = %User{username: "Ben Wilson"} |> Repo.insert!

    rows = [
      %{user_id: user1.id, title: "foo"},
      %{user_id: user2.id, title: "baz"},
    ]
    _ = Repo.insert_all(Post, rows)

    titles = [
      [post_title: "baz"],
      [post_title: "foo"],
    ]

    loader =
      loader
      |> Dataloader.load_many(Test, User, titles)
      |> Dataloader.run

    assert [user2, user1] == Dataloader.get_many(loader, Test, User, titles)
  end
end
