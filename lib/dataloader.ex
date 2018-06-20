defmodule Dataloader do
  defmodule GetError do
    defexception message:
                   "Failed to get data, this may mean it has not been loaded, see Dataloader documentation for more info."
  end

  @moduledoc """
  # Dataloader

  Dataloader provides an easy way efficiently load data in batches. It's
  inspired by https://github.com/facebook/dataloader, although it makes some
  small API changes to better suit Elixir use cases.

  Central to Dataloader is the idea of a source. A single Dataloader struct can
  have many different sources, which represent different ways to load data.

  Here's an example of a data loader using an ecto source, and then loading some
  organization data.

  ```elixir
  source = Dataloader.Ecto.new(MyApp.Repo)

  # setup the loader
  loader = Dataloader.new |> Dataloader.add_source(:db, source)

  # load some things
  loader =
    loader
    |> Dataloader.load(:db, Organization, 1)
    |> Dataloader.load_many(:db, Organization, [4, 9])

  # actually retrieve them
  loader = Dataloader.run(loader)

  # Now we can get whatever values out we want
  organizations = Dataloader.get_many(loader, :db, Organization, [1,4])
  ```

  This will do a single SQL query to get all organizations by ids 1,4, and 9.
  You can load multiple batches from multiple sources, and then when `run/1` is
  called batch will be loaded concurrently.

  Here we named the source `:db` within our dataloader. More commonly though if
  you're using Phoenix you'll want to name it after one of your contexts, and
  have a different source used for each context. This provides an easy way to
  enforce data access rules within each context. See the `DataLoader.Ecto`
  moduledocs for more details
  """
  defstruct sources: %{},
            options: []

  require Logger
  alias Dataloader.Source

  @type t :: %__MODULE__{
          sources: %{source_name => Dataloader.Source.t()},
          options: [option]
        }

  @type option :: {:timeout, pos_integer}
  @type source_name :: any

  @default_timeout 15_000

  @spec new([option]) :: t
  def new(opts \\ []), do: %__MODULE__{options: opts}

  @spec add_source(t, source_name, Dataloader.Source.t()) :: t
  def add_source(%{sources: sources} = loader, name, source) do
    sources = Map.put(sources, name, source)
    %{loader | sources: sources}
  end

  @spec load_many(t, source_name, any, [any]) :: t | no_return()
  def load_many(loader, source_name, batch_key, vals) when is_list(vals) do
    source =
      loader
      |> get_source(source_name)
      |> do_load(batch_key, vals)

    put_in(loader.sources[source_name], source)
  end

  @spec load(t, source_name, any, any) :: t | no_return()
  def load(loader, source_name, batch_key, val) do
    load_many(loader, source_name, batch_key, [val])
  end

  defp do_load(source, batch_key, vals) do
    Enum.reduce(vals, source, &Source.load(&2, batch_key, &1))
  end

  @spec run(t) :: t | no_return
  def run(dataloader) do
    if pending_batches?(dataloader) do
      fun = fn {name, source} -> {name, Source.run(source)} end

      sources =
        dataloader.sources
        |> pmap(
          fun,
          timeout: dataloader_timeout(dataloader)
        )
        |> Enum.map(fn
          {_source, {:ok, {name, source}}} -> {name, source}
          {_source, {:error, reason}} -> {:error, reason}
        end)
        |> Map.new()

      %{dataloader | sources: sources}
    else
      dataloader
    end
  end

  defp dataloader_timeout(dataloader) do
    max_source_timeout =
      dataloader.sources
      |> Enum.map(fn {_, source} -> Source.timeout(source) end)
      |> Enum.max()

    (max_source_timeout || @default_timeout) + :timer.seconds(1)
  end

  @spec get(t, source_name, any, any) :: any | no_return()
  def get(loader, source, batch_key, item_key) do
    loader
    |> get_source(source)
    |> Source.fetch(batch_key, item_key)
    |> do_get
  end

  # TODO: The nested ok's here are horrendous, as is the nil case. I need to
  # tidy this up to be more sane; it's likely because of the nested pmaps and
  # the way I've crowbarred in `KV`, need to revisit this.
  defp do_get({:ok, {:ok, {:error, reason}}}), do: raise(Dataloader.GetError, inspect(reason))
  defp do_get({:ok, {:ok, val}}), do: val

  # These two clauses are primarily for backwards compatibility with sources
  # that aren't returning appropriate ok/error tuples. This may or may not
  # survive the full refactor though.
  #
  # NOTE: Raising on error is a new behaviour though, that should arguably just
  # be `nil` if this is just for backwards compatibility
  defp do_get({:ok, val}), do: val
  defp do_get(:error), do: raise(Dataloader.GetError)

  @spec get_many(t, source_name, any, any) :: [any] | no_return()
  def get_many(loader, source, batch_key, item_keys) when is_list(item_keys) do
    source = get_source(loader, source)

    for key <- item_keys do
      source
      |> Source.fetch(batch_key, key)
      |> do_get
    end
  end

  def put(loader, source_name, batch_key, item_key, result) do
    source =
      loader
      |> get_source(source_name)
      |> Source.put(batch_key, item_key, result)

    put_in(loader.sources[source_name], source)
  end

  @spec pending_batches?(t) :: boolean
  def pending_batches?(loader) do
    Enum.any?(loader.sources, fn {_name, source} -> Source.pending_batches?(source) end)
  end

  defp get_source(loader, source_name) do
    loader.sources[source_name] || raise "Source does not exist: #{inspect(source_name)}"
  end

  @doc false
  # This function should be documented more completely, as it's a core function
  # used by both this module and both predefined sources. Spec should be (I
  # think!):
  #
  # @spec pmap(list(), fun(), keyword()) :: map({any(), any()})
  #
  # Current constraints that I'm questioning in this PR:
  #
  # - `fun` must return a `{key, result}` tuple
  # - If any `fun` errors for whatever reason, nothing gets added to the return
  #   value for that item, effectively swallowing any error
  # - There's not necessarily a relation between the `items` parameter and the
  #   keys in the returned map, so debugging is hard and the code is difficult
  #   to reason about
  #
  # Proposed changes:
  #
  # - Return a map where the keys are the originally passed-in `items`, rather
  #   than letting `fun` define them.
  # - `fun` should return an `:ok`/`:error` tuple with the result of the query.
  #   We have the keys already in `items`, so let's return a map keyed off of
  #   that. The key reason for this is that we now have all the info we need
  #   when accessing the data to either raise or return, rather than losing it
  #   completely.
  #     - NOTE: This isn't perfect yet though because of the reuse between
  #     `Dataloader.run` and `Source.run` implementations. The former has no
  #     concept of "keys" because it's just passing in sources  and assuming
  #     they come out the same way at the other end, whereas the other one has
  #     a concept of "keys" backed into it but hidden as part of a tuple in
  #     `items`. This is the main reason I consider this ripe for a refactor...
  # - Document!
  # - Consider renaming and extracting from here
  #
  def pmap(items, fun, opts \\ []) do
    options = [
      timeout: opts[:timeout] || @default_timeout,
      on_timeout: :kill_task
    ]

    # This supervisor exists to help ensure that the spawned tasks will die as
    # promptly as possible if the current process is killed.
    {:ok, task_super} = Task.Supervisor.start_link([])

    # The intermediary task is spawned here so that the `:trap_exit` flag does
    # not lead to rogue behaviour within the current process. This could happen
    # if the current process is linked to something, and then that something
    # dies in the middle of us loading stuff.
    task =
      Task.async(fn ->
        # The purpose of `:trap_exit` here is so that we can ensure that any failures
        # within the tasks do not kill the current process. We want to get results
        # back no matter what.
        Process.flag(:trap_exit, true)

        results =
          task_super
          |> Task.Supervisor.async_stream(items, fun, options)
          |> Enum.map(fn
            {:ok, result} -> {:ok, result}
            {:exit, reason} -> {:error, reason}
          end)

        # TODO: What about duplicate keys? I'm not sure this is enough. Write
        # some tests to clarify the behaviour here
        #
        # TODO: When called from `Dataloader.run/1`, the items are a list of
        # sources, so keying the results map off them is fine. But when we're
        # calling with sources, this appears to be a `{batch_key, batch}`
        # tuple, which makes this a bit odd to key off; or maybe not? Needs a
        # bit more thought.
        #
        Enum.zip(items, results)
        |> Map.new()
      end)

    # The infinity is safe here because the internal
    # tasks all have their own timeout.
    Task.await(task, :infinity)
  end
end
