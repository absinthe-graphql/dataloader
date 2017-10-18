if Code.ensure_loaded?(Ecto) do
  defmodule Dataloader.Ecto do
    @moduledoc """
    Ecto source for Dataloader

    This defines a schema and an implementation of the `Dataloader.Source` protocol
    for handling Ecto related batching.

    A simple Ecto source only needs to know about your application's Repo.

    ## Basic Usage

    ```elixir
    source = Dataloader.Ecto.new(MyApp.Repo)

    loader =
      Dataloader.new
      |> Dataloader.add_source(Accounts, source)
      |> Dataloader.load(Accounts, User, 1)
      |> Dataloader.load_many(Accounts, Organization, [4, 9])
      |> Dataloader.run

    organizations = Dataloader.get(loader, Accounts, Organization, [4,9])

    loader =
      loader
      |> Dataloader.load_many(Accounts, :users, organizations)
      |> Dataloader.run
    ```

    ## Filtering / Ordering

    `Dataloader.new/2` can receive a 2 arity function that can be used to apply
    broad ordering and filtering rules, as well as handle parameters

    ```elixir
    source = Dataloader.Ecto.new(MyApp.Repo, query: &Accounts.query/2)

    loader =
      Dataloader.new
      |> Dataloader.add_source(Accounts, source)
    ```

    When we call `load/4` we can pass in a tuple as the batch key

    ```
    loader
    |> Dataloader.load(Accounts, {User, order: :name}, 1)

    # or
    loader
    |> Dataloader.load_many(Accounts, {:users, order: :name}, organizations)

    # this is still supported
    loader
    |> Dataloader.load(Accounts, User, 1)
    ```

    In both cases the `Accounts.query` function would be:
    ```
    def query(User, params) do
      field = params[:order] || :id
      from u in User, order_by: [asc: field(u, ^field)]
    end
    def query(queryable, _) do
      queryable
    end
    ```

    If we query something that ends up using the `User` schema, whether directly
    or via association, the `query/2` function will match on the first clause and
    we can handle the params. If no params are supplied, the params arg defaults
    to `source.default_params` which itself defaults to `%{}`.

    `default_params` is an extremely useful place to store values like the current user:

    ```
    source = Dataloader.Ecto.new(MyApp.Repo, [
      query: &Accounts.query/2,
      default_params: %{current_user: current_user},
    ])

    loader =
      Dataloader.new
      |> Dataloader.add_source(Accounts, source)
      |> Dataloader.load_many(Accounts, Organization, ids)
      |> Dataloader.run

    # the query function
    def query(Organization, %{current_user: user}) do
      from o in Organization,
        join: m in assoc(o, :memberships),
        where: m.user_id == ^user.id
    end
    def query(queryable, _) do
      queryable
    end
    ```

    In our query function we are pattern matching on the current user to make sure
    that we are only able to lookup data in organizations that the user actually
    has a membership in. Additional options you specify IE `{Organization, %{order: :asc}}`
    are merged into the default.
    """

    defstruct [
      :repo,
      :query,
      batches: %{},
      results: %{},
      default_params: %{},
    ]

    def new(repo, opts \\ []) do
      opts = Keyword.put(opts, :query, opts[:query] || &query/2)

      %__MODULE__{repo: repo}
      |> struct(opts)
    end

    defp query(schema, _) do
      schema
    end

    defimpl Dataloader.Source do
      import Ecto.Query

      def run(source) do
        results = Map.new(source.batches, &run_batch(&1, source))
        # TODO: deep merge results
        %{source | results: results, batches: %{}}
      end

      def get(%{results: results} = source, batch, item) do
        batch = normalize_key(batch, source.default_params)
        {batch_key, item_key, _item} = get_keys(batch, item)
        results[batch_key][item_key]
      end

      def load(source, batch, item) do
        batch = normalize_key(batch, source.default_params)
        {batch_key, item_key, item} = get_keys(batch, item)
        entry = {item_key, item}
        update_in(source.batches, fn batches ->
          Map.update(batches, batch_key, [entry], &[entry | &1])
        end)
      end

      def pending_batches?(%{batches: batches}) do
        batches != %{}
      end

      defp get_keys({assoc_field, opts}, %schema{} = record) when is_atom(assoc_field) do
        primary_keys = schema.__schema__(:primary_key)
        id = Enum.map(primary_keys, &Map.get(record, &1))

        %{queryable: queryable, field: field} = schema.__schema__(:association, assoc_field)

        {{:assoc, self(), field, queryable, opts}, id, record}
      end
      defp get_keys({queryable, opts}, id) when is_atom(queryable) do
        {{:queryable, self(), queryable, opts}, id, id}
      end
      defp get_keys(key, item) do
        raise """
        Invalid: #{inspect key}
        #{inspect item}

        The batch key must either be a queryable, or an association name.
        """
      end

      defp normalize_key({key, params}, default_params) do
        {key, Enum.into(params, default_params)}
      end
      defp normalize_key(key, default_params), do: {key, default_params}

      defp run_batch({{:queryable, pid, queryable, opts} = key, ids}, source) do
        {ids, _} = Enum.unzip(ids)
        query = source.query.(queryable, opts)
        query = from s in query,
          where: s.id in ^ids

        results =
          query
          |> source.repo.all(caller: pid)
          |> Map.new(&{&1.id, &1})

        {key, results}
      end
      defp run_batch({{:assoc, pid, field, queryable, opts} = key, records}, source) do
        {ids, records} = Enum.unzip(records)

        query = source.query.(queryable, opts)
        query = Ecto.Queryable.to_query(query)

        results =
          records
          |> source.repo.preload([{field, query}], caller: pid)
          |> Enum.map(&Map.get(&1, field))

        {key, Map.new(Enum.zip(ids, results))}
      end
    end
  end
end
