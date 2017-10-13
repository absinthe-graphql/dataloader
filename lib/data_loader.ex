defmodule DataLoader do
  defstruct [
    sources: %{},
    options: [],
  ]

  alias DataLoader.Source

  def new(opts \\ []), do: %__MODULE__{options: opts}

  def add_source(loader, name, source) do
    Map.update!(loader, :sources, fn sources ->
      Map.put(sources, name, source)
    end)
  end

  def load_many(loader, source_name, batch_key, vals) when is_list(vals) do
    source =
      loader
      |> get_source(source_name)
      |> do_load(batch_key, vals)

    put_in(loader.sources[source_name], source)
  end

  def load(loader, source_name, batch_key, val) do
    load_many(loader, source_name, batch_key, [val])
  end

  defp do_load(source, batch_key, vals) do
    Enum.reduce(vals, source, &Source.load(&2, batch_key, &1))
  end

  def run(dataloader) do
    # TODO: pmap
    sources = Map.new(dataloader.sources, &run_source/1)
    %{dataloader | sources: sources}
  end

  def get(loader, source, batch_key, item_key) do
    loader
    |> get_source(source)
    |> Source.get(batch_key, item_key)
  end

  def get_many(loader, source, batch_key, item_keys) when is_list(item_keys) do
    source = get_source(loader, source)
    for key <- item_keys do
      Source.get(source, batch_key, key)
    end
  end

  def pending_batches?(loader) do
    Enum.any?(loader.sources, fn {_name, source} -> Source.pending_batches?(source) end)
  end

  defp get_source(loader, source_name) do
    loader.sources[source_name] || raise "Source does not exist: #{inspect source_name}"
  end

  defp run_source({name, source}) do
    {name, Source.run(source)}
  end

end
