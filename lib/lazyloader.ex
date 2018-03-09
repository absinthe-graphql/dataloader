defmodule Lazyloader do
  def new(), do: Lazyloader.Deferrable.new()

  def load_many(source_name, batch_key, vals) do
    Lazyloader.Deferrable.new()
    |> load_many(source_name, batch_key, vals)
  end

  def load_many(deferrable = %Lazyloader.Deferrable{}, source_name, batch_key, vals) do
    Lazyloader.Deferrable.add_operation(deferrable, {:load_many, [source_name, batch_key, vals]})
  end

  def load(source_name, batch_key, val) do
    Lazyloader.Deferrable.new()
    |> load(source_name, batch_key, val)
  end

  def load(deferrable = %Lazyloader.Deferrable{}, source_name, batch_key, val) do
    Lazyloader.Deferrable.add_operation(deferrable, {:load, [source_name, batch_key, val]})
  end

  def get(%Lazyloader.Deferrable{dataloader: nil}, _, _, _), do: raise("No dataloader found")

  def get(%Lazyloader.Deferrable{dataloader: loader}, source, batch_key, item_key) do
    Dataloader.get(loader, source, batch_key, item_key)
  end

  def get_many(
        %Lazyloader.Deferrable{dataloader: nil},
        _,
        _,
        item_keys
      )
      when is_list(item_keys),
      do: raise("No dataloader found")

  def get_many(
        %Lazyloader.Deferrable{dataloader: dataloader},
        source,
        batch_key,
        item_keys
      )
      when is_list(item_keys) do
    Dataloader.get_many(dataloader, source, batch_key, item_keys)
  end

  def put(source_name, batch_key, item_key, result) do
    Lazyloader.Deferrable.new()
    |> put(source_name, batch_key, item_key, result)
  end

  def put(deferrable = %Lazyloader.Deferrable{}, source_name, batch_key, item_key, result) do
    Lazyloader.Deferrable.add_operation(
      deferrable,
      {:put, [source_name, batch_key, item_key, result]}
    )
  end
end