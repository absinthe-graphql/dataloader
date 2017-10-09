if Code.ensure_loaded?(Ecto) do
  defmodule DataLoader.Ecto do
    @moduledoc """
    Ecto source for DataLoader

    This defines a schema and an implementation of the `DataLoader.Source` protocol
    for handling Ecto related batching.

    Ecto adds some specific challenges when using DataLoader
    """

    defstruct [
      :repo,
      :query,
      :caller,
      batches: %{},
      results: %{},
    ]

    def new(repo, opts \\ []) do
      %__MODULE__{
        repo: repo,
        caller: self(),
        query: Keyword.get(opts, :query, &query/3)
      }
    end

    defp query(schema, _, _ ) do
      schema
    end

    defimpl DataLoader.Source do
      import Ecto.Query

      def run(source) do
        results = Map.new(source.batches, &run_batch(&1, source))
        # TODO: deep merge results
        %{source | results: results, batches: %{}}
      end

      def get_result(%{results: results}, batch, item) do
        {batch_key, item_key} = classify(batch, item, [])
        results[batch_key][item_key]
      end

      defp classify(assoc_field, %schema{} = record, opts) when is_atom(assoc_field) do
        assoc = schema.__schema__(:association, assoc_field)
        primary_keys = schema.__schema__(:primary_key)
        id = Enum.map(primary_keys, &Map.get(record, &1))
        {{:assoc, assoc, opts}, {id, record}}
      end
      defp classify(queryable, id, opts) when is_atom(queryable) do
        {{:queryable, queryable, opts}, id}
      end
      defp classify(key, item, _) do
        raise """
        Invalid: #{inspect key}
        #{inspect item}

        The batch key must either be a queryable, or an association name.
        """
      end

      def pending_batches?(%{batches: batches}) do
        batches != %{}
      end

      def add(source, batch, item, _opts) do
        {batch_key, item} = classify(batch, item, [])
        update_in(source.batches, fn batches ->
          Map.update(batches, batch_key, [item], &[item | &1])
        end)
      end

      defp run_batch({{:queryable, queryable, opts} = key, ids}, source) do
        query = from s in queryable,
          where: s.id in ^ids

        results =
          query
          |> source.repo.all(caller: source.caller)
          |> Map.new(&{&1.id, &1})

        {key, results}
      end
    end
  end
end
