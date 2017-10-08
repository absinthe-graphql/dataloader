defmodule DataLoader do
  defstruct [
    sources: %{},
    options: [],
  ]

  alias DataLoader.Source

  def add_source(loader, name, source) do
    Map.update!(loader, :sources, fn sources ->
      Map.put(sources, name, source)
    end)
  end

  def add(loader, source_name, batch_key, item_key, item) do
    source =
      loader
      |> get_source(source_name)
      |> Source.add(batch_key, item_key, item)

    put_in(loader.sources[source_name], source)
  end

  def run(dataloader) do
    # TODO: pmap
    sources = Map.new(dataloader.sources, &run_source/1)
    %{dataloader | sources: sources}
  end

  def get_result(loader, source, batch_key, item_key) do
    loader
    |> get_source(source)
    |> Source.get_result(batch_key, item_key)
  end

  def pending_batches?(loader) do
    Enum.any?(loader.sources, fn {_name, source} -> Source.pending_batches?(source) end)
  end

  defp get_source(loader, source_name) do
    loader.sources[source_name] || raise "Source does not exist: #{source_name}"
  end

  defp run_source({name, source}) do
    {name, Source.run(source)}
  end

end
