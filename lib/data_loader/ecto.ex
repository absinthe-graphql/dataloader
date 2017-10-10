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
      batches: %{},
      results: %{},
    ]

    def new(repo, opts \\ []) do
      %__MODULE__{
        repo: repo,
        query: Keyword.get(opts, :query, &query/2)
      }
    end

    defp query(schema, _) do
      schema
    end

    defimpl DataLoader.Source do
      import Ecto.Query

      def run(source) do
        results = Map.new(source.batches, &run_batch(&1, source))
        # TODO: deep merge results
        %{source | results: results, batches: %{}}
      end

      def get(%{results: results}, batch, item) do
        batch = normalize_key(batch)
        {batch_key, item_key, _item} = get_keys(batch, item)
        results[batch_key][item_key]
      end

      def load(source, batch, item) do
        batch = normalize_key(batch)
        {batch_key, item_key, item} = get_keys(batch, item)
        entry = {item_key, item}
        update_in(source.batches, fn batches ->
          Map.update(batches, batch_key, [entry], &[entry | &1])
        end)
      end

      def pending_batches?(%{batches: batches}) do
        batches != %{}
      end

      defp get_keys({assoc_field, opts}, %schema{} = record) when is_atom(assoc_field) do
        primary_keys = schema.__schema__(:primary_key)
        id = Enum.map(primary_keys, &Map.get(record, &1))

        %{queryable: queryable, field: field} = schema.__schema__(:association, assoc_field)

        {{:assoc, self(), field, queryable, opts}, id, record}
      end
      defp get_keys({queryable, opts}, id) when is_atom(queryable) do
        {{:queryable, self(), queryable, opts}, id, id}
      end
      defp get_keys(key, item) do
        raise """
        Invalid: #{inspect key}
        #{inspect item}

        The batch key must either be a queryable, or an association name.
        """
      end

      defp normalize_key(tuple) when is_tuple(tuple) do
        tuple
      end
      defp normalize_key(key), do: {key, []}

      defp run_batch({{:queryable, pid, queryable, opts} = key, ids}, source) do
        {ids, _} = Enum.unzip(ids)
        query = source.query.(queryable, opts)
        query = from s in query,
          where: s.id in ^ids

        results =
          query
          |> source.repo.all(caller: pid)
          |> Map.new(&{&1.id, &1})

        {key, results}
      end
      defp run_batch({{:assoc, pid, field, queryable, opts} = key, records}, source) do
        {ids, records} = Enum.unzip(records)

        query = source.query.(queryable, opts)
        query = Ecto.Queryable.to_query(query)

        results =
          records
          |> source.repo.preload([{field, query}], caller: pid)
          |> Enum.map(&Map.get(&1, field))

        {key, Map.new(Enum.zip(ids, results))}
      end
    end
  end
end
