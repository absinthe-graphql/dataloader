if Code.ensure_loaded?(Ecto) do
  defmodule Dataloader.Ecto do
    @moduledoc """
    This defines an implementation of the `Dataloader.Source` protocol for handling Ecto-related batching.

    ## Basic Usage

    The basic usage of Dataloader for Ecto revolves around
    - query-ables as batch-keys, and
    - `{column, value}` tuples as item-keys.

    ### Querying by Primary Key

    Suppose we have a `:users` table with a corresponding `User` schema.
    If we wanted the user with `id: 1` and we were using Ecto, we'd use `Ecto.Repo.get/3`.
    With Dataloader, we use a multi-step process.

    Assuming we've already defined an Ecto source and added it to a loader like so:

    ```elixir
    # Ecto source
    ecto_source = Dataloader.Ecto.new(MyApp.Repo)

    # Loader with `ecto_source` named `:Accounts`
    loader =
      Dataloader.new()
      |> Dataloader.add_source(Accounts, ecto_source)
    ```

    We'd fetch the user with `id: 1` using the `User` schema as our batch-key and `1` as our item-key:

    ```elixir
    user_1 =
      loader
      |> Dataloader.load(Accounts, User, 1)
      |> Dataloader.run()
      |> Dataloader.get(Accounts, User, 1)
    ```

    Note how we used a `Dataloader.load/4` and `Dataloader.get/4` pair.
    That's because our item-key `1` was singular.

    If instead we wanted multiple item-keys, e.g. users corresponding to multiple IDs, we'd use a `Dataloader.load_many/4` and `Dataloader.get_many/4` pair:

    ```elixir
    [user_4, user_9] =
      loader
      |> Dataloader.load_many(Accounts, User, [4, 9])
      |> Dataloader.run()
      |> Dataloader.get_many(Accounts, User, [4, 9])
    ```

    We can also combine `Dataloader.load/4`, `Dataloader.load_many/4`, `Dataloader.get/4`, and `Dataloader.get_many/4`:

    ```elixir
    loader_with_users_1_4_and_9 =
      loader
      |> Dataloader.load(Accounts, User, 1)
      |> Dataloader.load_many(Accounts, User, [4, 9])
      |> Dataloader.run()

    [user_1, user_9] =
      loader_with_users_1_4_and_9
      |> Dataloader.get_many(Accounts, User, [1, 9])

    user_4 =
      loader_with_users_1_4_and_9
      |> Dataloader.get(Accounts, User, 4)
    ```

    ### Querying by (Non-Primary Key) Column

    When getting a user by primary key (`:id`), we supplied the `:id` itself: `1`.
    Dataloader interpreted that as asking for the column whose `:id` was `1`.
    We can ask for records by other columns as well.

    Suppose our `:users` table has a `:name` column and our `User` schema has a `:name` field.
    If we want the user with the name `"admin"`, we can do:

    ```elixir
    user_named_admin =
      loader
      |> Dataloader.load(Accounts, {:one, User}, name: "admin")
      |> Dataloader.run()
      |> Dataloader.get(Accounts, {:one, User}, name: "admin")
    ```

    There are two things to note here:

    1.  We passed our column constraint as an item-key: `[name: "admin"]`.
        Importantly, it's only possible to query by one column at a time in this way.
        So the Keyword list item-key may only have length one.
        For more complex queries, see "Advanced Usage" below.

    2.  We specified the _cardinality_ of the expected result via: `{:one, User}`.
        Cardinality determines whether Dataloader should return a single value or a list of values.
        Cardinality is required because unlike with database keys, multiple records may match a column constraint.
        The `{:one, _}` / `{:many, _}` distinction is analogous to using `Ecto.Repo.one/1` or `Ecto.Repo.all/1`, respectively.

    If instead we expected multiple users to match `[name: "admin"]`, we'd use `{:many, User}`:

    ```elixir
    user_named_admin =
      loader
      |> Dataloader.load(Accounts, {:many, User}, name: "admin")
      |> Dataloader.run()
      |> Dataloader.get(Accounts, {:many, User}, name: "admin")
    ```

    Note also that for both `{:one, User}` and `{:many, User}`, we used `Dataloader.load/4`, not `Dataloader.load_many/4`.
    This is because even if we expect Dataloader to return multiple values, we're still only passing a single item-key: `{:name, "admin"}`.

    Remember:
    - `Dataloader.load/4` vs. `Dataloader.load_many/4` refers to the number of _item-keys_.
    - `{:one, _}` vs. `{:many, _}` refers to the number of _expected return values_.

    ### Querying by Association

    So far when querying by column, our item-keys were `{column, value}` tuples and our batch-keys were either schema modules or `{cardinality, module}` tuples.
    We can also use schema structs as our item-keys and their associations as our batch-keys.

    Suppose in our schema, all users belong to an organization.
    That is, the `:users` table has an `organization_id` column that references an `:organizations` table with a corresponding `Organization` schema.

    If we want to lookup the organization for `user_1`, we can do that by providing the `user_1` struct as the item-key and the `:organization` association as the batch-key.
    Note that this requires that our `User` schema has a `belongs_to(:organization)`.

    ```elixir
    organization_for_user_1 =
      loader
      |> Dataloader.load(Accounts, :organization, user_1)
      |> Dataloader.run()
      |> Dataloader.get(Accounts, :organization, user_1)
    ```

    We could also do the reverse.
    We look up the `:users` association on `organization_for_user_1`.
    Note that this requires that in our Ecto schema, `Organization` has a `has_many(:users)`.

    ```elixir
    all_users_in_user_1s_organization =
      loader
      |> Dataloader.load_many(Accounts, :users, organization_for_user_1)
      |> Dataloader.run()
      |> Dataloader.get_many(Accounts, :users, organization_for_user_1)
    ```

    We can even load all the users for multiple organizations.

    ```elixir
    orgs_100_and_101 =
      loader
      |> Dataloader.load_many(Accounts, :organizations, [100, 101])
      |> Dataloader.run()
      |> Dataloader.get_many(Accounts, :organizations, [100, 101])

    [users_in_org_100, users_in_org_101] =
      loader
      |> Dataloader.load_many(Accounts, :users, orgs_100_and_101)
      |> Dataloader.run()
      |> Dataloader.get_many(Accounts, :users, orgs_100_and_101)
    ```

    ## Advanced Usage

    So far, we've seen how we can batch on

    - primary key columns,
    - non-primary key columns (with cardinality), and
    - associations.

    Unfortunately, these options alone are often insufficient.
    What if we wanted to order the results by a particular column?
    Or join to another table?

    As we'll see, we can gain greater control over what queries are run by providing callbacks to `Dataloader.Ecto.new/2`.

    ### Filtering & Ordering with the `:query` Option

    `Dataloader.load/4` and `Dataloader.load_many/4` allow generic parameters to be part of the batch-key:

    ```elixir
    loader
    |> Dataloader.load(source, {schema_module_or_association, my_parameters}, item_key)
    ```

    When present, these parameters are passed to a 2-arity callback function.
    You can provide this callback when you create a source using `Dataloader.Ecto.new/2` via a `:query` option:

    ```elixir
    source = Dataloader.Ecto.new(MyApp.Repo,
      query: &my_query_callback/2
    )

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Accounts, source)
    ```

    As an example, suppose we want to allow users to be ordered by any column.
    We might design for an optional `:order_by` parameter in our batch-keys:

    ```elixir
    loader
    |> Dataloader.load(Accounts, {User, %{order_by: :name}}, 1)
    #                                   ^----------------^
    #                                   parameters
    ```

    Then we'd have our callback look for that option when the queryable was the `User` schema:

    ```elixir
    def my_query_callback(User, %{order_by: order_by}) do
      from u in User, order_by: [asc: field(u, ^order_by)]
    end

    def my_query_callback(queryable, _) do
      queryable
    end
    ```

    If we query something that ends up using the `User` schema, whether directly or via association, `my_query_callback/2` will match on the first clause and we can handle the params.
    Otherwise, none of our parameters were passed in and the queryable should remain as is.
    So it's important to give the callback a default clause!

    ### Default Query Parameters with the `:default_params` Option

    You can also provide default parameters via a `:default_params` option.

    For example, it's common for users to not be allowed to access an organization if they're not a member.
    In this use case, `:default_params` is an extremely useful place to store the current user:

    ```elixir
    # source
    source = Dataloader.Ecto.new(MyApp.Repo,
      query: &query/2,
      default_params: %{current_user: current_user},
    )

    # callback
    def query(Organization, %{current_user: user}) do
      from o in Organization,
        join: m in assoc(o, :memberships),
        where: m.user_id == ^user.id
    end

    def query(queryable, _) do
      queryable
    end
    ```

    Now for every query attempting to access the `Organization` schema, regardless of if a `:current_user` option is passed in, `Organization` is scoped to the `:current_user`.
    So in the following query:

    ```elixir
    organizations_scoped_to_current_user =
      Dataloader.new()
      |> Dataloader.add_source(Accounts, source)
      |> Dataloader.load_many(Accounts, Organization, ids)
      |> Dataloader.run()
      |> Dataloader.get_many(Accounts, Organization, ids)
    ```

    The organizations in `organizations_scoped_to_current_user` only contain those from `ids` where the current user is a member.
    The rest are discarded even though the query itself didn't reference `:current_user`.

    Note that additional options you specify in the batch-key are merged into, and will override, the default.

    ### Custom Batch Queries with the `:run_batch` Option

    The Dataloader flow is generally:

    ```elixir
    result =
      Dataloader.new()
      |> Dataloader.add_source(source_name, source)
      |> Dataloader.load(source_name, batch_key, item_key)
      |> Dataloader.run() # <-- no control over this step yet
      |> Dataloader.get(source_name, batch_key, item_key)
    ```

    With this flow, we've been able to achieve our goals by running basic queries, essentially:

    ```elixir
    from(q in Queryable, where: field(q, ^col) == ^val)
    ```

    maybe with some extra `:where`s or an `:order_by` tacked on by a `:query` callback.
    We've not yet built more complicated queries nor run the queries ourself.
    If we require this level of control, we can do both these things with the `:run_batch` option to `Dataloader.Ecto.new/2`.

    For example, suppose our users make posts, and posts have categories.
    That is, we have a `"posts"` table with `user_id` and `category` columns.
    Our `Post` schema has a `belongs_to(:user)` and `field(:category)`.

    If we want all users who've made a post in a certain category, how would we do this?
    We can't do it by any combination of `:where` clauses on the `"users"` table because the category information is in the `"posts"` table.
    Similarly, querying the `"posts"` table won't work because it won't return users, only posts with a user's ID.
    We need to join.

    Unfortunately, there's no mechanism in the basic usage to join to another table.
    We could feasibly add a join in a `:query` callback, but there are downsides to this approach.
    See "Using `:query` vs. `:run_batch`" for more details.

    So, we're left with using `:run_batch`.
    Similar to how we would achieve custom results with `:query`, we will design for a custom parameter -- `:post_category` -- which is not found under the `User` schema.
    This time, however, we include the parameter in the _item-key_.

    Suppose we wanted all users who've posted under the `"Foo"` category.
    First, we would load the `{:post_category, "Foo"}` item-key under the `{:many, User}` batch-key (since we want _all_ the users who've posted in category `"Foo"`).

    ```elixir
    loader
    |> Dataloader.load(Source, {:many, User}, post_category: "Foo")
    ```

    As `:post_category` is not present under the `User` schema, Dataloader will try to match on it when it runs the batch.
    So, we must provide a `:run_batch` callback with a clause that includes `:post_category` in the 3rd argument:

    ```elixir
    def run_batch(User, query, :post_category, categories, repo_opts) do
      query =
        from(u in query,
          join: p in assoc(u, :posts),
          where: p.category in ^categories,
          select: {p.category, u}
        )

      results =
        query
        |> Repo.all(repo_opts)
        |> Enum.group_by(
          fn {category, _} -> category end,
          fn {_, user} -> user end
        )

      for category <- categories, do: Map.get(results, category, [])
    end

    # Fallback to original run_batch
    def run_batch(queryable, query, col, inputs, repo_opts) do
      Dataloader.Ecto.run_batch(Repo, queryable, query, col, inputs, repo_opts)
    end
    ```

    There are several things to note here:

    - `run_batch/5` was passed a Queryable (`User`) and a query (`query`).
      While we could have done `from(u in User, ...)`, we instead did `from(u in query, ...)`.
      That's because `query` may have passed through a `:query` callback and been altered.
      If we queried `User` directly, we would have lost any changes the `:query` callback may have added.
      (See example below.)

    - `run_batch/5` was not passed a singular category `"Foo"`, but a list of categories.
      `run_batch/5` is always passed a list of inputs.

    - Similarly, `run_batch/5` returned a list of _list of_ users.
      `run_batch/5` must always return a list with an order analogous to the order of `inputs` (`["Foo"]` in our example).
      If we'd had `inputs = ["Foo", "Bar"]`, we'd return `[foo_users, bar_users]`.
      If we'd had `inputs = ["Bar", "Foo"]`, we'd return `[bar_users, foo_users]`.
      This is why we see `[]` as the default in `Map.get(results, category, [])`.
      If no users were found for a category, we'd return an empty list for that category.

    - Just like with `:query`, we needed a default clause.

    #### `:run_batch` with `:query`

    Since `:run_batch` operates on the item-keys and `:query` operates on the batch-keys, they can operate completely independently of each other.

    To illustrate, suppose our users' posts can also be published.
    That is, the `"posts"` table has a boolean `published` column.
    Let's add some example data:

    ```elixir
    [user_1, user_2] = [%User{id: 1}, %User{id: 2}]

    posts = [
      %{user_id: user_1.id, category: "Foo", published: true},
      %{user_id: user_2.id, category: "Foo", published: false},
      %{user_id: user_2.id, category: "Bar", published: true}
    ]

    _ = Repo.insert_all(Post, posts)
    ```

    Assuming our `:run_batch` callback from above is still defined, let's also add a `:query` callback:

    ```elixir
    def query(Post, %{published: published}) do
      from(p in Post,
        where: p.published == ^published
      )
    end

    def query(queryable, _) do
      queryable
    end

    source =
      Dataloader.Ecto.new(
        Repo,
        query: &query/2,
        run_batch: &run_batch/5
      )

    loader =
      Dataloader.new()
      |> Dataloader.add_source(Accounts, source)
    ```

    Now we can use `:query` and `:run_batch` together:

    ```elixir
    loader =
    loader
    |> Dataloader.load(Accounts, {:many, User}, post_category: "Foo")
    |> Dataloader.load(Accounts, {:many, User, %{published: true}}, post_category: "Foo")
    |> Dataloader.run()

    # Returns user_1 and user_2
    Dataloader.get(loader, Accounts, {:many, User}, post_category: "Foo")
    # Returns user_2 only
    Dataloader.get(loader, Accounts, {:many, User}, post_category: "Bar")
    # Returns user_1 and user_2
    Dataloader.get(loader, Accounts, {:many, User, %{published: true}})
    # Returns user_1 only
    Dataloader.get(loader, Accounts, {:many, User, %{published: true}}, post_category: "Foo")
    ```

    ### [TODO] Using `:query` vs. `:run_batch`

    TODO

    ## [WIP] Quick References

    ### Batch-Keys

    Batch-keys are always 3-tuples.
    In some cases, you can provide a subset of the tuple and Dataloader will infer the rest.

    - **General Form**
      - `{cardinality, schema_module_or_association, parameters}`
        - `cardinality`
          - `:one` or `:many`
          - determines the expected number of returned records
        - `schema_module_or_association`
          - Schema module (e.g. `User`) or
          - Association (e.g. `:organization`)
        - `parameters`
          - map of parameters (e.g. `%{published: true}`)
          - passed to `:query` callback

    - **Examples**
      Batch-Key | Resolves To | Valid When
      :-- | :-- | :--
      `{:many, User, %{deleted: false}}` | `{:many, User, %{deleted: false}}` | Always
      `{:many, User}` | `{:many, User, %{}}` | parameters = `%{}`
      `{:one, User}` | `{:one, User, %{}}` | parameters = `%{}`
      `{User, %{deleted: false}}` | `{:many, User, %{deleted: false}}` | Always
      `{User, %{deleted: false}}` | `{:one, User, %{deleted: false}}` | item-key is a primary key
      `User` | `{:one, User, %{}}` | item-key is a primary key and parameters = `%{}`

    ### Item-Keys

    Item-keys are always a list with a single, 2-tuple element.

    - **General Form**
      - `{column_or_parameter, value}`
        - `column_or_parameter`
          - Column (e.g. `:name`)
          - Parameter (e.g. `:post_category`)
        - `value`
          - Value (e.g. `"Alfred"`)

    - **Examples**
      Item-Key | Resolves To | Valid When
      :-- | :-- | :--
      `[{:name, "Alfred"}]` | `[{:name, "Alfred"}]` | Always
      `1` | `[{:id, 1}]` | Always (assumes `:id` is a primary key)
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
            repo_opts: repo_opts,
            batches: map,
            results: map,
            default_params: map,
            run_batch: batch_fun,
            options: Keyword.t()
          }

    @type query_fun :: (Ecto.Queryable.t(), any -> Ecto.Queryable.t())
    @type repo_opts :: Keyword.t()
    @type batch_fun :: (Ecto.Queryable.t(), Ecto.Query.t(), any, [any], repo_opts -> [any])
    @type opt ::
            {:query, query_fun}
            | {:default_params, Map.t()}
            | {:repo_opts, repo_opts}
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
    @spec run_batch(
            repo :: Ecto.Repo.t(),
            queryable :: Ecto.Queryable.t(),
            query :: Ecto.Query.t(),
            col :: any,
            inputs :: [any],
            repo_opts :: repo_opts
          ) :: [any]
    def run_batch(repo, queryable, query, col, inputs, repo_opts) do
      results = load_rows(col, inputs, queryable, query, repo, repo_opts)
      grouped_results = group_results(results, col)

      for value <- inputs do
        grouped_results
        |> Map.get(value, [])
        |> Enum.reverse()
      end
    end

    defp load_rows(col, inputs, queryable, query, repo, repo_opts) do
      case query do
        %Ecto.Query{limit: limit, offset: offset} when not is_nil(limit) or not is_nil(offset) ->
          load_rows_lateral(col, inputs, queryable, query, repo, repo_opts)

        _ ->
          query
          |> where([q], field(q, ^col) in ^inputs)
          |> repo.all(repo_opts)
      end
    end

    defp load_rows_lateral(col, inputs, queryable, query, repo, repo_opts) do
      # Approximate a postgres unnest with a subquery
      inputs_query =
        queryable
        |> where([q], field(q, ^col) in ^inputs)
        |> select(^[col])
        |> distinct(true)

      query =
        query
        |> where([q], field(q, ^col) == field(parent_as(:input), ^col))

      from(input in subquery(inputs_query), as: :input)
      |> join(:inner_lateral, q in subquery(query))
      |> select([_input, q], q)
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
        {batch_key, item_key, _item} =
          batch_key
          |> normalize_key(source.default_params)
          |> get_keys(item)

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
            fn {:ok, map} -> {:ok, Map.put(map, item_key, result)} end
          )

        %{source | results: results}
      end

      def load(source, batch, item) do
        {batch_key, item_key, item} =
          batch
          |> normalize_key(source.default_params)
          |> get_keys(item)

        if fetched?(source.results, batch_key, item_key) do
          source
        else
          entry = {item_key, item}

          update_in(source.batches, fn batches ->
            Map.update(batches, batch_key, MapSet.new([entry]), &MapSet.put(&1, entry))
          end)
        end
      end

      defp fetched?(results, batch_key, item_key) do
        case results do
          %{^batch_key => {:ok, %{^item_key => _}}} -> true
          _ -> false
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

          %Ecto.Association.HasThrough{through: [through_field | through_fields]} ->
            [through_field | through_fields ++ fields]
            |> chase_down_queryable(schema)
        end
      end

      defp get_keys({assoc_field, opts}, %schema{} = record) when is_atom(assoc_field) do
        validate_queryable(schema)
        primary_keys = schema.__schema__(:primary_key)
        id = Enum.map(primary_keys, &Map.get(record, &1))

        queryable = chase_down_queryable([assoc_field], schema)

        {{:assoc, schema, self(), assoc_field, queryable, opts}, id, record}
      end

      defp get_keys({{cardinality, queryable}, opts}, value) when is_atom(queryable) do
        validate_queryable(queryable)
        {_, col, value} = normalize_value(queryable, value)
        {{:queryable, self(), queryable, cardinality, col, opts}, value, value}
      end

      defp get_keys({queryable, opts}, value) when is_atom(queryable) do
        validate_queryable(queryable)

        case normalize_value(queryable, value) do
          {:primary, col, value} ->
            {{:queryable, self(), queryable, :one, col, opts}, value, value}

          {:not_primary, col, _value} ->
            raise """
            Cardinality required unless using primary key

            The non-primary key column specified was: #{inspect(col)}
            """
        end
      end

      defp get_keys(key, item) do
        raise """
        Invalid: #{inspect(key)}
        #{inspect(item)}

        The batch key must either be a schema module, or an association name.
        """
      end

      defp validate_queryable(queryable) do
        unless {:__schema__, 1} in queryable.__info__(:functions) do
          raise "The given module - #{queryable} - is not an Ecto schema."
        end
      rescue
        _ in UndefinedFunctionError ->
          raise Dataloader.GetError, """
            The given atom - #{inspect(queryable)} - is not a module.

            This can happen if you intend to pass an Ecto struct in your call to
            `dataloader/4` but pass something other than a struct.
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

      def run_batches(source) do
        options = [
          timeout: source.options[:timeout] || Dataloader.default_timeout(),
          on_timeout: :kill_task
        ]

        results =
          source.batches
          |> Task.async_stream(
            fn batch ->
              id = :erlang.unique_integer()
              system_time = System.system_time()
              start_time_mono = System.monotonic_time()

              emit_start_event(id, system_time, batch)
              batch_result = run_batch(batch, source)
              emit_stop_event(id, start_time_mono, batch)

              batch_result
            end,
            options
          )
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

        coerced_inputs =
          if type = queryable.__schema__(:type, col) do
            for input <- inputs do
              {:ok, input} = Ecto.Type.cast(type, input)
              input
            end
          else
            inputs
          end

        results =
          queryable
          |> source.run_batch.(query, col, coerced_inputs, repo_opts)
          |> Enum.map(cardinality_mapper)

        results =
          inputs
          |> Enum.zip(results)
          |> Map.new()

        {key, results}
      end

      defp run_batch({{:assoc, schema, pid, field, queryable, opts} = key, records}, source) do
        {ids, records} = Enum.unzip(records)
        query = source.query.(queryable, opts) |> Ecto.Queryable.to_query()
        repo_opts = Keyword.put(source.repo_opts, :caller, pid)
        empty = schema |> struct |> Map.fetch!(field)
        records = records |> Enum.map(&Map.put(&1, field, empty))

        results =
          if query.limit || query.offset do
            records
            |> preload_lateral(field, query, source.repo, repo_opts)
          else
            records
            |> source.repo.preload([{field, query}], repo_opts)
          end

        results = results |> Enum.map(&Map.get(&1, field))
        {key, Map.new(Enum.zip(ids, results))}
      end

      def preload_lateral([], _assoc, _query, _opts), do: []

      def preload_lateral([%schema{} | _] = structs, assoc, query, repo, repo_opts) do
        [pk] = schema.__schema__(:primary_key)

        assocs = expand_assocs(schema, [assoc])

        inner_query =
          assocs
          |> Enum.reverse()
          |> build_preload_lateral_query(query, :join_first)
          |> maybe_distinct(assocs)

        results =
          from(x in schema,
            as: :parent,
            inner_lateral_join: y in subquery(inner_query),
            where: field(x, ^pk) in ^Enum.map(structs, &Map.get(&1, pk)),
            select: {field(x, ^pk), y}
          )
          |> repo.all(repo_opts)

        {keyed, default} =
          case schema.__schema__(:association, assoc) do
            %{cardinality: :one} ->
              {results |> Map.new(), nil}

            %{cardinality: :many} ->
              {Enum.group_by(results, fn {k, _} -> k end, fn {_, v} -> v end), []}
          end

        structs
        |> Enum.map(&Map.put(&1, assoc, Map.get(keyed, Map.get(&1, pk), default)))
      end

      defp expand_assocs(_schema, []), do: []

      defp expand_assocs(schema, [assoc | rest]) do
        case schema.__schema__(:association, assoc) do
          %Ecto.Association.HasThrough{through: through} ->
            expand_assocs(schema, through ++ rest)

          a ->
            [a | expand_assocs(a.queryable, rest)]
        end
      end

      defp build_preload_lateral_query(
             [%Ecto.Association.ManyToMany{} = assoc],
             query,
             :join_first
           ) do
        [{owner_join_key, owner_key}, {related_join_key, related_key}] = assoc.join_keys

        query
        |> join(:inner, [x], y in ^assoc.join_through,
          on: field(x, ^related_key) == field(y, ^related_join_key)
        )
        |> where([..., x], field(x, ^owner_join_key) == field(parent_as(:parent), ^owner_key))
      end

      defp build_preload_lateral_query(
             [%Ecto.Association.ManyToMany{} = assoc],
             query,
             :join_last
           ) do
        [{owner_join_key, owner_key}, {related_join_key, related_key}] = assoc.join_keys

        query
        |> join(:inner, [..., x], y in ^assoc.join_through,
          on: field(x, ^related_key) == field(y, ^related_join_key)
        )
        |> where([..., x], field(x, ^owner_join_key) == field(parent_as(:parent), ^owner_key))
      end

      defp build_preload_lateral_query([assoc], query, :join_first) do
        query
        |> where([x], field(x, ^assoc.related_key) == field(parent_as(:parent), ^assoc.owner_key))
      end

      defp build_preload_lateral_query([assoc], query, :join_last) do
        query
        |> where(
          [..., x],
          field(x, ^assoc.related_key) == field(parent_as(:parent), ^assoc.owner_key)
        )
      end

      defp build_preload_lateral_query(
             [%Ecto.Association.ManyToMany{} = assoc | rest],
             query,
             :join_first
           ) do
        [{owner_join_key, owner_key}, {related_join_key, related_key}] = assoc.join_keys

        query =
          query
          |> join(:inner, [x], y in ^assoc.join_through,
            on: field(x, ^related_key) == field(y, ^related_join_key)
          )
          |> join(:inner, [..., x], y in ^assoc.owner,
            on: field(x, ^owner_join_key) == field(y, ^owner_key)
          )

        build_preload_lateral_query(rest, query, :join_last)
      end

      defp build_preload_lateral_query(
             [%Ecto.Association.ManyToMany{} = assoc | rest],
             query,
             :join_last
           ) do
        [{owner_join_key, owner_key}, {related_join_key, related_key}] = assoc.join_keys

        query =
          query
          |> join(:inner, [..., x], y in ^assoc.join_through,
            on: field(x, ^related_key) == field(y, ^related_join_key)
          )
          |> join(:inner, [..., x], y in ^assoc.owner,
            on: field(x, ^owner_join_key) == field(y, ^owner_key)
          )

        build_preload_lateral_query(rest, query, :join_last)
      end

      defp build_preload_lateral_query([assoc | rest], query, :join_first) do
        query =
          query
          |> join(:inner, [x], y in ^assoc.owner,
            on: field(x, ^assoc.related_key) == field(y, ^assoc.owner_key)
          )

        build_preload_lateral_query(rest, query, :join_last)
      end

      defp build_preload_lateral_query([assoc | rest], query, :join_last) do
        query =
          query
          |> join(:inner, [..., x], y in ^assoc.owner,
            on: field(x, ^assoc.related_key) == field(y, ^assoc.owner_key)
          )

        build_preload_lateral_query(rest, query, :join_last)
      end

      defp maybe_distinct(query, [%Ecto.Association.Has{}, %Ecto.Association.BelongsTo{} | _]) do
        distinct(query, true)
      end

      defp maybe_distinct(query, [%Ecto.Association.ManyToMany{} | _]), do: distinct(query, true)
      defp maybe_distinct(query, [_assoc | rest]), do: maybe_distinct(query, rest)
      defp maybe_distinct(query, []), do: query

      defp emit_start_event(id, system_time, batch) do
        :telemetry.execute(
          [:dataloader, :source, :batch, :run, :start],
          %{system_time: system_time},
          %{id: id, batch: batch}
        )
      end

      defp emit_stop_event(id, start_time_mono, batch) do
        :telemetry.execute(
          [:dataloader, :source, :batch, :run, :stop],
          %{duration: System.monotonic_time() - start_time_mono},
          %{id: id, batch: batch}
        )
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
