defmodule Dataloader.KV do
  @moduledoc """
  Simple KV based Dataloader source.

  This module is a simple key value based data loader source. You
  must supply a function that accepts ids, and returns a map of values
  keyed by id.

  ## Examples

  """

  defstruct [
    :name,
    :load_function,
    opts: [],
    batches: %{},
    results: %{}
  ]

  def new(load_function, opts \\ []) do
    max_concurrency = opts[:max_concurrency] || System.schedulers_online() * 2

    %__MODULE__{
      load_function: load_function,
      opts: [
        max_concurrency: max_concurrency,
        timeout: opts[:timeout] || 30_000
      ]
    }
  end

  defimpl Dataloader.Source do
    # def merge(_, _), do: raise("Merge not supported on KV yet")
    defp merge_results(results_a, results_b) do
      Map.merge(results_a, results_b, fn _, v1, v2 ->
        Map.merge(v1, v2)
      end)
    end

    defp merge_batches(batches_a, batches_b) do
      Map.merge(batches_a, batches_b, fn _, v1, v2 ->
        v1 ++ v2
      end)
    end

    def merge(source_a, source_b) do
      %{
        source_a
        | results: merge_results(source_a.results, source_b.results),
          batches: merge_batches(source_a.batches, source_b.batches)
      }
    end

    def put(source, _batch, _id, nil) do
      source
    end

    def put(source, batch, id, result) do
      results = Map.update(source.results, batch, %{id => result}, &Map.put(&1, id, result))
      %{source | results: results}
    end

    def load(source, batch_key, id) do
      case fetch(source, batch_key, id) do
        :error ->
          update_in(source.batches[batch_key], fn
            nil -> [id]
            ids -> [id | ids]
          end)

        _ ->
          source
      end
    end

    def fetch(source, batch_key, id) do
      with {:ok, batch} <- Map.fetch(source.results, batch_key) do
        Map.fetch(batch, id)
      end
    end

    def run(source) do
      results =
        source.batches
        |> Dataloader.pmap(
          fn {batch_key, ids} ->
            {batch_key, source.load_function.(batch_key, ids)}
          end,
          []
        )

      %{source | batches: %{}, results: Map.merge(source.results, results)}
    end

    def pending_batches?(source) do
      source.batches != %{}
    end
  end
end