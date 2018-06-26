defmodule Dataloader.TestSource do
  defstruct [opts: [], batches: [], results: %{}]

  defimpl Dataloader.Source do

    def load(source, _batch_key, _item_key), do: source

    def fetch(_source, _batch_key, _item_key), do: :error

    def pending_batches?(_source), do: true

    def put(source, _batch_key, _item_key, _item), do: source

    def run(source) do
      Process.sleep(5) # Just needs to be larger than our Dataloader timeout
      source
    end
  end
end
