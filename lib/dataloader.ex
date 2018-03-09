defmodule Dataloader do
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
            callback_results: %{},
            options: []

  require Logger
  alias Dataloader.Source

  @type t :: %__MODULE__{
          sources: %{source_name => Dataloader.Source.t()},
          callback_results: map,
          options: [option]
        }

  @type option :: {:timeout, pos_integer}
  @type source_name :: any

  @spec new([option]) :: t
  def new(opts \\ []), do: %__MODULE__{options: opts}

  @spec add_source(t, source_name, Dataloader.Source.t()) :: t
  def add_source(%{sources: sources} = loader, name, source) do
    sources = Map.put(sources, name, %{source | name: name})
    %{loader | sources: sources}
  end

  def add_source(%{sources: sources} = loader, source) do
    if !source.name, do: raise("The source does not have a name")
    sources = Map.put(sources, source.name, source)
    %{loader | sources: sources}
  end

  @spec load_many(t, source_name, any, [any]) :: t | no_return()
  def load_many(source_name, batch_key, vals) do
    Dataloader.Deferrable.new()
    |> load_many(source_name, batch_key, vals)
  end

  def load_many(deferrable = %Dataloader.Deferrable{}, source_name, batch_key, vals) do
    Dataloader.Deferrable.add_operation(deferrable, {:load_many, [source_name, batch_key, vals]})
  end

  def load_many(loader, source_name, batch_key, vals) when is_list(vals) do
    source =
      loader
      |> get_source(source_name)
      |> do_load(batch_key, vals)

    put_in(loader.sources[source_name], source)
  end

  @spec load(t, source_name, any, any) :: t | no_return()
  def load(source_name, batch_key, val) do
    Dataloader.Deferrable.new()
    |> load(source_name, batch_key, val)
  end

  def load(deferrable = %Dataloader.Deferrable{}, source_name, batch_key, val) do
    Dataloader.Deferrable.add_operation(deferrable, {:load, [source_name, batch_key, val]})
  end

  def load(loader, source_name, batch_key, val) do
    load_many(loader, source_name, batch_key, [val])
  end

  defp do_load(source, batch_key, vals) do
    Enum.reduce(vals, source, &Source.load(&2, batch_key, &1))
  end

  # defp merge([dataloader]), do: dataloader

  # defp merge([dataloader_1, dataloader_2 | dataloaders]) do
  #   if Map.keys(dataloader_1.sources) != Map.keys(dataloader_2.sources),
  #     do: raise("Unable to merge dataloaders, dataloaders contain different sources")

  #   merge([
  #     %{
  #       dataloader_1
  #       | sources:
  #           Enum.zip(dataloader_1.sources, dataloader_2.sources)
  #           |> Enum.map(fn {{source_name, source_1}, {_, source_2}} ->
  #             {source_name, Source.merge(source_1, source_2)}
  #           end)
  #           |> Map.new()
  #     }
  #     | dataloaders
  #   ])
  # end

  # defp get_callback_result(_dataloader, res = %__MODULE__.Value{lazy?: false}), do: res

  # defp get_callback_result(
  #        dataloader,
  #        res = %__MODULE__.Value{
  #          lazy?: true,
  #          callback: nil,
  #          value: value,
  #          chained_callbacks: [chained_callback | chained_callbacks]
  #        }
  #      ) do
  #   case Map.fetch(dataloader.callback_results, {chained_callback, value}) do
  #     {:ok, value = %__MODULE__.Value{}} ->
  #       %{value | chained_callbacks: chained_callbacks}

  #     {:ok, non_wrapped_value} ->
  #       %__MODULE__.Value{res | value: non_wrapped_value, chained_callbacks: chained_callbacks}

  #     :error ->
  #       raise("Chained callback not found!")
  #   end
  # end

  # defp get_callback_result(
  #        dataloader,
  #        res = %__MODULE__.Value{
  #          lazy?: true,
  #          callback: callback,
  #          chained_callbacks: chained_callbacks
  #        }
  #      ) do
  #   case Map.fetch(dataloader.callback_results, callback) do
  #     {:ok, value = %__MODULE__.Value{}} ->
  #       %{value | chained_callbacks: chained_callbacks}

  #     {:ok, non_wrapped_value} ->
  #       %__MODULE__.Value{
  #         res
  #         | lazy?: chained_callbacks != [],
  #           value: non_wrapped_value,
  #           callback: nil
  #       }

  #     :error ->
  #       raise("Callback result not found")
  #   end
  # end

  # def evaluate_single_pass(results)

  # def evaluate_single_pass([]), do: []

  # def evaluate_single_pass(results) when is_list(results) do
  #   callbacks =
  #     Enum.map(results, fn
  #       %{lazy?: true, chained_callbacks: [chained_callback | _], callback: nil, value: value} ->
  #         {chained_callback, value}

  #       %{lazy?: true, callback: callback} ->
  #         callback

  #       _ ->
  #         nil
  #     end)
  #     |> Enum.filter(& &1)

  #   dataloader =
  #     results
  #     |> Enum.map(& &1.dataloader)
  #     |> merge()
  #     |> run(callbacks)

  #   Enum.map(results, &get_callback_result(dataloader, &1))
  # end

  # def evaluate_single_pass(res = %__MODULE__.Value{lazy?: false}), do: res

  # def evaluate_single_pass(
  #       res = %__MODULE__.Value{
  #         lazy?: true,
  #         value: value,
  #         callback: nil,
  #         chained_callbacks: [chained_callback | _chained_callbacks],
  #         dataloader: dataloader
  #       }
  #     ) do
  #   run(dataloader, [{chained_callback, value}])
  #   |> get_callback_result(res)
  # end

  # def evaluate_single_pass(
  #       res = %__MODULE__.Value{lazy?: true, dataloader: dataloader, callback: callback}
  #     ) do
  #   run(dataloader, [callback])
  #   |> get_callback_result(res)
  # end

  # def evaluate(res = %__MODULE__.Value{lazy?: false}), do: res

  # def evaluate(list_of_res) when is_list(list_of_res) do
  #   if Enum.any?(list_of_res, & &1.lazy?) do
  #     list_of_res
  #     |> evaluate_single_pass()
  #     |> evaluate()
  #   else
  #     list_of_res
  #   end
  # end

  # def evaluate(value) do
  #   value
  #   |> evaluate_single_pass()
  #   |> evaluate()
  # end

  # def get_value(%__MODULE__.Value{value: value, lazy?: false}), do: value

  # def get_value(%__MODULE__.Value{value: value, lazy?: true}),
  #   do: value |> evaluate |> get_value()

  # def get_value(values) when is_list(values) do
  #   values |> evaluate |> Enum.map(&get_value(&1))
  # end

  # defp build_non_lazy(_dataloader, %__MODULE__.Value{lazy?: true}),
  #   do: raise("expected evaluated value")

  # defp build_non_lazy(_dataloader, val = %__MODULE__.Value{}) do
  #   val
  # end

  # defp build_non_lazy(dataloader, val) do
  #   %__MODULE__.Value{value: val, dataloader: dataloader, lazy?: false}
  # end

  @spec run(t) :: t | no_return
  def run(dataloader) do
    dataloader =
      if pending_batches?(dataloader) do
        fun = fn {name, source} ->
          {name, Source.run(source)}
        end

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

    # callbacks =
    #   callbacks
    #   |> Enum.map(fn callback ->
    #     if !dataloader.callback_results[callback], do: callback
    #   end)
    #   |> Enum.filter(& &1)

    # Enum.reduce(callbacks, dataloader, fn callback, dataloader ->
    #   %{
    #     dataloader
    #     | callback_results:
    #         Map.put(
    #           dataloader.callback_results,
    #           callback,
    #           case callback do
    #             {callback, value} -> callback.(build_non_lazy(dataloader, value))
    #             callback -> callback.(dataloader)
    #           end
    #         )
    #   }
    # end)
  end

  def get(%Dataloader.Deferrable{dataloader: nil}, _, _, _), do: raise("No dataloader found")

  def get(%Dataloader.Deferrable{dataloader: loader}, source, batch_key, item_key) do
    get(loader, source, batch_key, item_key)
  end

  def get(loader, source, batch_key, item_key) do
    loader
    |> get_source(source)
    |> Source.fetch(batch_key, item_key)
    |> do_get
  end

  defp do_get({:ok, val}), do: val
  defp do_get(:error), do: nil

  @spec get_many(t, source_name, any, any) :: [any] | no_return()
  def get_many(source, batch_key, item_keys) when is_list(item_keys) do
    Dataloader.Deferrable.new()
    |> get_many(source, batch_key, item_keys)
  end

  def get_many(deferrable = %Dataloader.Deferrable{}, source, batch_key, item_keys)
      when is_list(item_keys) do
    Dataloader.Deferrable.add_operation(deferrable, {:get_many, [source, batch_key, item_keys]})
  end

  def get_many(loader, source, batch_key, item_keys) when is_list(item_keys) do
    source = get_source(loader, source)

    for key <- item_keys do
      source
      |> Source.fetch(batch_key, key)
      |> do_get
    end
  end

  def put(source_name, batch_key, item_key, result) do
    __MODULE__.Deferrable.new()
    |> put(source_name, batch_key, item_key, result)
  end

  def put(deferrable = %Dataloader.Deferrable{}, source_name, batch_key, item_key, result) do
    Dataloader.Deferrable.add_operation(
      deferrable,
      {:put, [source_name, batch_key, item_key, result]}
    )
  end

  def put(loader, source_name, batch_key, item_key, result) do
    source =
      loader
      |> get_source(source_name)
      |> Source.put(batch_key, item_key, result)

    put_in(loader.sources[source_name], source)
  end

  # def then(
  #       prev = %__MODULE__.Value{lazy?: true, chained_callbacks: chained_callbacks},
  #       chained_callback
  #     ) do
  #   %{
  #     prev
  #     | chained_callbacks: Enum.reverse([chained_callback | chained_callbacks])
  #   }
  # end

  def deferrable(), do: %__MODULE__.Deferrable{}

  # def get_value(%__MODULE__.Value)

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

    # This supervisor exists to help ensure that the spawned tasks will die as
    # promptly as possible if the current process is killed.
    {:ok, task_super} = Task.Supervisor.start_link([])

    # The intermediary task is spawned here so that the `:trap_exit` flag does
    # not lead to rogue behaviour within the current process. This could happen
    # if the current process is linked to something, and then that something
    # does in the middle of us loading stuff.
    task =
      Task.async(fn ->
        # The purpose of `:trap_exit` here is so that we can ensure that any failures
        # within the tasks do not kill the current process. We want to get results
        # back no matter what.
        Process.flag(:trap_exit, true)

        task_super
        |> Task.Supervisor.async_stream(items, fun, options)
        |> Enum.reduce(%{}, fn
          {:ok, {key, value}}, results ->
            Map.put(results, key, value)

          _, results ->
            results
        end)
      end)

    # The infinity is safe here because the internal
    # tasks all have their own timeout.
    Task.await(task, :infinity)
  end
end