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
  enforce data access rules within each context. See the `Dataloader.Ecto`
  moduledocs for more details

  ## Options

  There are two configuration options:

  * `timeout` - The maximum timeout to wait for running a source, defaults to
    1s more than the maximum timeout of all added sources. Set with care,
    timeouts should really only be set on sources.
  * `get_policy` - This configures how the dataloader will behave when fetching
    data which may have errored when we tried  to `load` it.

  These can be set as part of the `new/1` call. So, for example, to
  configure a dataloader that returns `nil` on error with a 5s timeout:

  ```elixir
  loader =
    Dataloader.new(
      get_policy: :return_nil_on_error,
      timeout: :timer.seconds(5)
    )
  ```

  ### `get_policy`

  There are three implemented behaviours for this:

  * `raise_on_error` (default)- If successful, calling `get/4` or `get_many/4`
    will return the value. If there was an exception when trying to load any of
    the data, it will raise that exception
  * `return_nil_on_error` - Behaves similar to `raise_on_error` but will just
    return `nil` instead of `raising`. It will still log errors
  * `tuples` - This will return `{:ok, value}`/`{:error, reason}` tuples
    depending on a successful or failed load, allowing for more fine-grained
    error handling if required

  """
  defstruct sources: %{},
            options: [],
            task: Task

  alias Dataloader.Source

  @type t :: %__MODULE__{
          sources: %{source_name => Dataloader.Source.t()},
          options: [option]
        }

  @type option :: {:timeout, pos_integer} | {:get_policy, atom()}
  @type source_name :: any

  @default_timeout 15_000
  def default_timeout, do: @default_timeout

  @default_get_policy :raise_on_error

  @doc """
  Create a new Dataloader instance.

  See moduledoc for available options
  """
  @spec new([option]) :: t
  def new(opts \\ []) do
    {task, opts} = Keyword.pop(opts, :task, Task)

    opts =
      [get_policy: @default_get_policy]
      |> Keyword.merge(opts)

    %__MODULE__{options: opts, task: task}
  end

  @spec add_source(t, source_name, Dataloader.Source.t()) :: t
  def add_source(%{sources: sources} = loader, name, source) do
    # TODO: Need to pass in a reference to dataloader.async here.

    sources = Map.put(sources, name, source)
    %{loader | sources: sources}
  end

  @spec load_many(t, source_name, any, [any]) :: t
  def load_many(loader, source_name, batch_key, vals) when is_list(vals) do
    source =
      loader
      |> get_source(source_name)
      |> do_load(batch_key, vals)

    put_in(loader.sources[source_name], source)
  end

  @spec load(t, source_name, any, any) :: t
  def load(loader, source_name, batch_key, val) do
    load_many(loader, source_name, batch_key, [val])
  end

  defp do_load(source, batch_key, vals) do
    Enum.reduce(vals, source, &Source.load(&2, batch_key, &1))
  end

  @spec run(t) :: t
  def run(dataloader) do
    if pending_batches?(dataloader) do
      id = :erlang.unique_integer()
      system_time = System.system_time()
      start_time_mono = System.monotonic_time()

      emit_start_event(id, system_time, dataloader)

      sources =
        Dataloader.Async.tasks(
          dataloader,
          dataloader.sources,
          fn {name, source} -> {name, Source.run(source, dataloader)} end,
          timeout: timeout(dataloader)
        )
        |> Enum.map(fn
          {_source, {:ok, {name, source}}} -> {name, source}
          {_source, {:error, reason}} -> {:error, reason}
        end)
        |> Map.new()

      updated_dataloader = %{dataloader | sources: sources}

      emit_stop_event(id, start_time_mono, updated_dataloader)

      updated_dataloader
    else
      dataloader
    end
  end

  defp emit_start_event(id, system_time, dataloader) do
    :telemetry.execute(
      [:dataloader, :source, :run, :start],
      %{system_time: system_time},
      %{id: id, dataloader: dataloader}
    )
  end

  defp emit_stop_event(id, start_time_mono, dataloader) do
    :telemetry.execute(
      [:dataloader, :source, :run, :stop],
      %{duration: System.monotonic_time() - start_time_mono},
      %{id: id, dataloader: dataloader}
    )
  end

  def timeout(dataloader) do
    max_source_timeout =
      dataloader.sources
      |> Enum.map(fn {_, source} -> Source.timeout(source) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> @default_timeout end)

    max_source_timeout + :timer.seconds(1)
  end

  @spec get(t, source_name, any, any) :: any
  def get(loader = %Dataloader{options: options}, source, batch_key, item_key) do
    loader
    |> get_source(source)
    |> Source.fetch(batch_key, item_key)
    |> do_get(options[:get_policy])
  end

  @spec get_many(t, source_name, any, any) :: [any] | {:ok, [any]}
  def get_many(loader = %Dataloader{options: options}, source, batch_key, item_keys)
      when is_list(item_keys) do
    source = get_source(loader, source)

    for key <- item_keys do
      source
      |> Source.fetch(batch_key, key)
      |> do_get(options[:get_policy])
    end
  end

  defp do_get({:ok, val}, :raise_on_error), do: val
  defp do_get({:ok, val}, :return_nil_on_error), do: val
  defp do_get({:ok, val}, :tuples), do: {:ok, val}

  defp do_get({:error, reason}, :raise_on_error), do: raise(Dataloader.GetError, inspect(reason))
  defp do_get({:error, _reason}, :return_nil_on_error), do: nil
  defp do_get({:error, reason}, :tuples), do: {:error, reason}

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
    loader.sources[source_name] ||
      raise """
      Source does not exist: #{inspect(source_name)}

      Registered sources are:

      #{inspect(Enum.map(loader.sources, fn {source, _} -> source end))}
      """
  end

  @doc """
  This used to be used by both the `Dataloader` module for running multiple
  source queries concurrently, and the `KV` and `Ecto` sources to actually run
  separate batch fetches (e.g. for `Posts` and `Users` at the same time).

  The problem was that the behaviour between the sources and the parent
  `Dataloader` was actually slightly different. The `Dataloader`-specific
  behaviour has been pulled out into `run_tasks/4`

  Please use `async_safely/3` instead of this for fetching data from sources
  """
  @doc deprecated: "Use async_safely/3 instead"
  @spec pmap(list(), fun(), keyword()) :: map()
  def pmap(items, fun, opts \\ []) do
    Dataloader.Async.tasks(%Dataloader{}, items, fun, opts)
  end
end
