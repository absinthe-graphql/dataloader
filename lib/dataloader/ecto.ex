if Code.ensure_loaded?(Ecto) do
  defmodule Dataloader.Ecto do
    @moduledoc """
    Ecto source for Dataloader

    This defines a schema and an implementation of the `Dataloader.Source` protocol
    for handling Ecto related batching.

    A simple Ecto source only needs to know about your application's Repo.

    ## Basic Usage

    Querying by primary key (analogous to Ecto.Repo.get/3):

    ```elixir
    source = Dataloader.Ecto.new(MyApp.Repo)

    loader =
      Dataloader.new
      |> Dataloader.add_source(Accounts, source)
      |> Dataloader.load(Accounts, User, 1)
      |> Dataloader.load_many(Accounts, Organization, [4, 9])
      |> Dataloader.run

    organizations = Dataloader.get(loader, Accounts, Organization, [4,9])
    ```

    Querying for associations. Here we look up the `:users` association on all
    the organizations, and the :organization for a single user.

    ```elixir
    loader =
      loader
      |> Dataloader.load(Accounts, :organization, user)
      |> Dataloader.load_many(Accounts, :users, organizations)
      |> Dataloader.run
    ```

    Querying by a column other than the primary key:

    ```elixir
    loader =
      loader
      |> Dataloader.load(Accounts, {:one, User}, name: "admin")
      |> Dataloader.run
    ```

    Here we pass a keyword list of length one. It is only possible to
    query by one column here; for more complex queries, see "filtering" below.

    Notice here that we need to also specify the cardinality in the batch_key
    (`:many` or `:one`), which will decide whether to return a list or a single
    value (or nil). This is because the column may not be a key and there may be
    multiple matching records. Note also that even if we are returning `:many` values
    here  from multiple matching records, this is still a call to `load/4` rather than
    `load_many/4` because there is only one val specified.

    ## Filtering / Ordering

    `Dataloader.new/2` can receive a 2 arity function that can be used to apply
    broad ordering and filtering rules, as well as handle parameters

    ```elixir
    source = Dataloader.Ecto.new(MyApp.Repo, query: &Accounts.query/2)

    loader =
      Dataloader.new
      |> Dataloader.add_source(Accounts, source)
    ```

    When we call `load/4` we can pass in a tuple as the batch key with a keyword list
    of parameters in addition to the queryable or assoc_field

    ```elixir
    # with a queryable
    loader
    |> Dataloader.load(Accounts, {User, order: :name}, 1)

    # or an association
    loader
    |> Dataloader.load_many(Accounts, {:users, order: :name}, organizations)

    # this is still supported
    loader
    |> Dataloader.load(Accounts, User, 1)

    # as is this
    loader
    |> Dataloader.load(:accounts, :user, organization)
    ```

    In all cases the `Accounts.query` function would be:
    ```elixir
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

    ```elixir
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
      :run_batch,
      repo_opts: [],
      batches: %{},
      results: %{},
      default_params: %{},
      options: []
    ]

    @type t :: %__MODULE__{
            repo: Ecto.Repo.t(),
            query: query_fun,
            repo_opts: Keyword.t(),
            batches: map,
            results: map,
            default_params: map,
            run_batch: batch_fun,
            options: Keyword.t()
          }

    @type query_fun :: (Ecto.Queryable.t(), any -> Ecto.Queryable.t())
    @type batch_fun :: (Ecto.Queryable.t(), Ecto.Query.t(), [any], Keyword.t() -> [any])
    @type opt ::
            {:query, query_fun}
            | {:repo_opts, Keyword.t()}
            | {:timeout, pos_integer}
            | {:run_batch, batch_fun()}

    import Ecto.Query

    @doc """
    Create an Ecto Dataloader source.

    This module handles retrieving data from Ecto for dataloader. It requires a
    valid Ecto Repo. It also accepts a `repo_opts:` option which is handy for
    applying options to any calls to Repo functions that this module makes.

    For example, you can use this module in a multi-tenant context by using
    the `prefix` option:

    ```
    Dataloader.Ecto.new(MyApp.Repo, repo_opts: [prefix: "tenant"])
    ```
    """
    @spec new(Ecto.Repo.t(), [opt]) :: t
    def new(repo, opts \\ []) do
      data =
        opts
        |> Keyword.put_new(:query, &query/2)
        |> Keyword.put_new(:run_batch, &run_batch(repo, &1, &2, &3, &4, &5))

      opts = Keyword.take(opts, [:timeout])

      %__MODULE__{repo: repo, options: opts}
      |> struct(data)
    end

    @doc """
    Default implementation for loading a batch. Handles looking up records by
    column
    """
    def run_batch(repo, _queryable, query, col, inputs, repo_opts) do
      results = load_rows(col, inputs, query, repo, repo_opts)
      grouped_results = group_results(results, col)

      for value <- inputs do
        grouped_results
        |> Map.get(value, [])
        |> Enum.reverse()
      end
    end

    defp load_rows(col, inputs, query, repo, repo_opts) do
      query
      |> where([q], field(q, ^col) in ^inputs)
      |> repo.all(repo_opts)
    end

    defp group_results(results, col) do
      results
      |> Enum.reduce(%{}, fn result, grouped ->
        value = Map.get(result, col)
        Map.update(grouped, value, [result], &[result | &1])
      end)
    end

    defp query(schema, _) do
      schema
    end

    defimpl Dataloader.Source do
      def run(source) do
        results = Dataloader.async_safely(__MODULE__, :run_batches, [source])

        results =
          Map.merge(source.results, results, fn _, {:ok, v1}, {:ok, v2} ->
            {:ok, Map.merge(v1, v2)}
          end)

        %{source | results: results, batches: %{}}
      end

      def fetch(source, batch_key, item) do
        normalized_batch_key = normalize_key(batch_key, source.default_params)

        {batch_key, item_key, _item} = get_keys(normalized_batch_key, item)

        with {:ok, batch} <- Map.fetch(source.results, batch_key) do
          fetch_item_from_batch(batch, item_key)
        else
          :error ->
            {:error, "Unable to find batch #{inspect(batch_key)}"}
        end
      end

      defp fetch_item_from_batch(tried_and_failed = {:error, _reason}, _item_key),
        do: tried_and_failed

      defp fetch_item_from_batch({:ok, batch}, item_key) do
        case Map.fetch(batch, item_key) do
          :error -> {:error, "Unable to find item #{inspect(item_key)} in batch"}
          result -> result
        end
      end

      def put(source, _batch, _item, %Ecto.Association.NotLoaded{}) do
        source
      end

      def put(source, batch, item, result) do
        batch = normalize_key(batch, source.default_params)
        {batch_key, item_key, _item} = get_keys(batch, item)

        results =
          Map.update(
            source.results,
            batch_key,
            {:ok, %{item_key => result}},
            &Map.put(&1, item_key, result)
          )

        %{source | results: results}
      end

      def load(source, batch, item) do
        case fetch(source, batch, item) do
          {:error, _message} ->
            batch = normalize_key(batch, source.default_params)
            {batch_key, item_key, item} = get_keys(batch, item)
            entry = {item_key, item}

            update_in(source.batches, fn batches ->
              Map.update(batches, batch_key, MapSet.new([entry]), &MapSet.put(&1, entry))
            end)

          _ ->
            source
        end
      end

      def pending_batches?(%{batches: batches}) do
        batches != %{}
      end

      def timeout(%{options: options}) do
        options[:timeout]
      end

      defp chase_down_queryable([field], schema) do
        case schema.__schema__(:association, field) do
          %{queryable: queryable} ->
            queryable

          %Ecto.Association.HasThrough{through: through} ->
            chase_down_queryable(through, schema)

          val ->
            raise """
            Valid association #{field} not found on schema #{inspect(schema)}
            Got: #{inspect(val)}
            """
        end
      end

      defp chase_down_queryable([field | fields], schema) do
        case schema.__schema__(:association, field) do
          %{queryable: queryable} ->
            chase_down_queryable(fields, queryable)
        end
      end

      defp get_keys({assoc_field, opts}, %schema{} = record) when is_atom(assoc_field) do
        primary_keys = schema.__schema__(:primary_key)
        id = Enum.map(primary_keys, &Map.get(record, &1))

        queryable = chase_down_queryable([assoc_field], schema)

        {{:assoc, schema, self(), assoc_field, queryable, opts}, id, record}
      end

      defp get_keys({{cardinality, queryable}, opts}, value) when is_atom(queryable) do
        {_, col, value} = normalize_value(queryable, value)
        {{:queryable, self(), queryable, cardinality, col, opts}, value, value}
      end

      defp get_keys({queryable, opts}, value) when is_atom(queryable) do
        case normalize_value(queryable, value) do
          {:primary, col, value} ->
            {{:queryable, self(), queryable, :one, col, opts}, value, value}

          _ ->
            raise "cardinality required unless using primary key"
        end
      end

      defp get_keys(key, item) do
        raise """
        Invalid: #{inspect(key)}
        #{inspect(item)}

        The batch key must either be a schema module, or an association name.
        """
      end

      defp normalize_value(queryable, [{col, value}]) do
        case queryable.__schema__(:primary_key) do
          [^col] ->
            {:primary, col, value}

          _ ->
            {:not_primary, col, value}
        end
      end

      defp normalize_value(queryable, value) do
        [primary_key] = queryable.__schema__(:primary_key)
        {:primary, primary_key, value}
      end

      # This code was totally OK until cardinalities showed up. Now it's ugly :(
      # It is however correct, which is nice.
      @cardinalities [:one, :many]

      defp normalize_key({cardinality, queryable}, default_params)
           when cardinality in @cardinalities do
        normalize_key({{cardinality, queryable}, []}, default_params)
      end

      defp normalize_key({cardinality, queryable, params}, default_params)
           when cardinality in @cardinalities do
        normalize_key({{cardinality, queryable}, params}, default_params)
      end

      defp normalize_key({key, params}, default_params) do
        {key, Enum.into(params, default_params)}
      end

      defp normalize_key(key, default_params) do
        {key, default_params}
      end

      def run_batches(task_supervisor, source) do
        options = [
          timeout: source.options[:timeout] || Dataloader.default_timeout(),
          on_timeout: :kill_task
        ]

        results =
          task_supervisor
          |> Task.Supervisor.async_stream(source.batches, &run_batch(&1, source), options)
          |> Enum.map(fn
            {:ok, {_key, result}} -> {:ok, result}
            {:exit, reason} -> {:error, reason}
          end)

        source.batches
        |> Enum.map(fn {key, _set} -> key end)
        |> Enum.zip(results)
        |> Map.new()
      end

      defp run_batch(
             {{:queryable, pid, queryable, cardinality, col, opts} = key, entries},
             source
           ) do
        inputs = Enum.map(entries, &elem(&1, 0))

        query = source.query.(queryable, opts)

        repo_opts = Keyword.put(source.repo_opts, :caller, pid)

        cardinality_mapper = cardinality_mapper(cardinality, queryable)

        results =
          queryable
          |> source.run_batch.(query, col, inputs, repo_opts)
          |> Enum.map(cardinality_mapper)

        results =
          inputs
          |> Enum.zip(results)
          |> Map.new()

        {key, results}
      end

      defp run_batch({{:assoc, schema, pid, field, queryable, opts} = key, records}, source) do
        {ids, records} = Enum.unzip(records)

        query = source.query.(queryable, opts)
        query = Ecto.Queryable.to_query(query)

        repo_opts = Keyword.put(source.repo_opts, :caller, pid)

        empty = schema |> struct |> Map.fetch!(field)

        results =
          records
          |> Enum.map(&Map.put(&1, field, empty))
          |> source.repo.preload([{field, query}], repo_opts)
          |> Enum.map(&Map.get(&1, field))

        {key, Map.new(Enum.zip(ids, results))}
      end

      defp cardinality_mapper(:many, _) do
        fn
          value when is_list(value) -> value
          value -> [value]
        end
      end

      defp cardinality_mapper(:one, queryable) do
        fn
          [] ->
            nil

          [value] ->
            value

          other when is_list(other) ->
            raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)

          other ->
            other
        end
      end
    end
  end
end
