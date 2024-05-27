defmodule Dataloader.Source.Error do
  defstruct []

  defimpl Dataloader.Source do
    def run(_source), do: Process.exit(self(), :kill)

    def load(source, _batch_key, _item_key), do: source
    def fetch(_source, _batch_key, _item_key), do: {:error, nil}
    def pending_batches?(_source), do: true
    def put(source, _batch_key, _item_key, _item), do: source
    def timeout(_source), do: 1
    def async?(_source), do: true
  end
end
