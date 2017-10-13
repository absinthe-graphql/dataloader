defmodule DataLoader.KV do
  @moduledoc """
  Simple KV based DataLoader source.

  This module is a simple key value based data loader source. You
  must supply a function that accepts ids, and returns a map of values
  keyed by id.
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

  defimpl DataLoader.Source do
    def load(source, batch_key, id) do
      case get(source, batch_key, id) do
        nil ->
          update_in(source.batches[batch_key], fn
            nil -> [id]
            ids -> [id | ids]
          end)
        _ ->
          source # cached
      end
    end

    def get(source, batch_key, id) do
      source.results[batch_key][id]
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
