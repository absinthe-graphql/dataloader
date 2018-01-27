defmodule Dataloader do
  @moduledoc """
  # Dataloader

  Dataloader provides an easy way efficiently load data in batches. It's
  inspired by https://github.com/facebook/dataloader, although it makes some
  small API changes to better suite Elixir use cases.

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

  alias Dataloader.Source

  @type t :: %__MODULE__{
          sources: %{source_name => Dataloader.Source.t()},
          options: [option]
        }

  @type option :: {:timeout, pos_integer}
  @type source_name :: any

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
          tag: "Source",
          timeout: dataloader.options[:timeout] || 15_000
        )
        |> Map.new()

      %{dataloader | sources: sources}
    else
      dataloader
    end
  end

  defp collect_failures(tasks_and_results, failures \\ [], success \\ [])

  defp collect_failures([], [] = _failures, success) do
    {:ok, Map.new(success)}
  end

  defp collect_failures([], failures, _acc) do
    {:error, failures}
  end

  defp collect_failures([{{:ok, result}, _} | rest], failures, success) do
    collect_failures(rest, failures, [result | success])
  end

  defp collect_failures([{{:exit, e}, item} | rest], failures, success) do
    collect_failures(rest, [{item, e} | failures], success)
  end

  defp shutdown_tasks(tasks, refs) do
    for {task, res} <- tasks do
      with nil <- res || Task.shutdown(task, :brutal_kill) do
        {:error, Map.fetch!(refs, task.ref)}
      end
    end
  end

  @spec get(t, source_name, any, any) :: any | no_return()
  def get(loader, source, batch_key, item_key) do
    loader
    |> get_source(source)
    |> Source.fetch(batch_key, item_key)
    |> do_get
  end

  defp do_get({:ok, val}), do: val
  defp do_get(:error), do: nil

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
  def pmap(items, fun, opts) do
    options = [
      timeout: opts[:timeout] || 15_000,
      on_timeout: :kill_task
    ]

    items
    |> Task.async_stream(fun, options)
    |> Enum.zip(items)
    |> collect_failures
    |> case do
      {:ok, results} ->
        results

      {:error, failures} ->
        raise """
        #{opts[:tag] || "Batch"} did not complete within #{options[:timeout]}
        Timed out: #{inspect(failures)}
        """
    end
  end
end
