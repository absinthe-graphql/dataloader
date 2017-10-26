defmodule Dataloader.KV do
  @moduledoc """
  Simple KV based Dataloader source.

  This module is a simple key value based data loader source. You
  must supply a function that accepts ids, and returns a map of values
  keyed by id.

  ## Examples

  """

  defstruct [
    :load_function,
    opts: [],
    batches: %{},
    results: %{},
  ]

  def new(load_function, opts \\ []) do
    max_concurrency = opts[:max_concurrency] || System.schedulers_online * 2
    %__MODULE__{
      load_function: load_function,
      opts: [
        max_concurrency: max_concurrency,
        timeout: opts[:timeout] || 30_000,
      ]
    }
  end

  defimpl Dataloader.Source do
    def put(source, batch, id, result) do
      batches = Map.update(source.batches, batch, %{id => result}, &Map.put(&1, id, result))
      %{source | batches: batches}
    end

    def load(source, batch_key, id) do
      case fetch(source, batch_key, id) do
        :error ->
          update_in(source.batches[batch_key], fn
            nil -> [id]
            ids -> [id | ids]
          end)
        source ->
          source
      end
    end

    def fetch(source, batch_key, id) do
      with {:ok, batch} <- Map.fetch(source, batch_key) do
        Map.fetch(batch, id)
      end
    end

    def run(source) do
      results =
        source.batches
        |> Task.async_stream(fn {batch_key, ids} ->
          source.load_function(batch_key, ids)
        end, source.opts)
        |> Map.new

      %{source |
        batches: %{},
        results: Map.merge(source.results, results),
      }
    end

    def pending_batches?(source) do
      source.batches != %{}
    end
  end
end
