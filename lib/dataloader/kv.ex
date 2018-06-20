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
    defp merge_results(existing_results, new_results) do
      new_results
      |> Enum.reduce(existing_results, fn {batch_info, data}, acc ->
        case data do
          {:error, reason} ->
            merge_errors(acc, batch_info, reason)

          {:ok, data} ->
            merge(acc, Map.new([data]))
        end
      end)
    end

    # TODO: Why is this different from success? The data being passed around
    # must still be a little inconsistent, so need to dig in a bit more
    defp merge_errors(acc, {batch_key, batch}, reason) do
      errors =
        batch
        |> Enum.reduce(%{}, fn key, acc ->
          Map.put(acc, key, {:error, reason})
        end)

      merge(acc, %{batch_key => errors})
    end

    defp merge(acc, results) do
      Map.merge(acc, results, fn _, v1, v2 ->
        Map.merge(v1, v2)
      end)
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
          update_in(source.batches, fn batches ->
            Map.update(batches, batch_key, MapSet.new([id]), &MapSet.put(&1, id))
          end)

        _ ->
          source
      end
    end

    def fetch(source, batch_key, id) do
      with {:ok, batch} <- Map.fetch(source.results, batch_key) do
        {:ok, Map.fetch(batch, id)}
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

      %{source | batches: %{}, results: merge_results(source.results, results)}
    end

    def pending_batches?(source) do
      source.batches != %{}
    end

    def timeout(%{opts: opts}) do
      opts[:timeout]
    end
  end
end
