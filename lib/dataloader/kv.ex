defmodule Dataloader.KV do
  @moduledoc """
  Simple KV based Dataloader source.

  This module is a simple key value based data loader source. You
  must supply a function that accepts ids, and returns a map of values
  keyed by id.

  ## Example

  ```elixir
  def datasource do
    Dataloader.KV.new(&query/2, max_concurrency: 1)
  end

  def query(:comments, posts) do
    Map.new(posts, fn %{id: post_id} = post ->
      {post, Comments.find_by(post_id: post_id)}
    end)
  end
  ```

  """

  defstruct [
    :load_function,
    opts: [],
    batches: %{},
    results: %{}
  ]

  @doc """
  Create a KV Dataloader source.

  Dataloader runs tasks concurrently using `Task.async_stream/3`. The
  concurrency of a KV Dataloader source and the time tasks are allowed to run
  can be controlled via options (see the "Options" section below).

  ## Options

    * `:max_concurrency` - sets the maximum number of tasks to run at the same
      time. Defaults to twice the number of schedulers online (see
      `System.schedulers_online/0`).
    * `:timeout` - the maximum amount of time (in milliseconds) a task is
      allowed to execute for. Defaults to `30000`.
  """
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
      if fetched?(source.results, batch_key, id) do
        source
      else
        update_in(source.batches, fn batches ->
          Map.update(batches, batch_key, MapSet.new([id]), &MapSet.put(&1, id))
        end)
      end
    end

    defp fetched?(results, batch_key, id) do
      case results do
        %{^batch_key => %{^id => {:error, _}}} -> false
        %{^batch_key => %{^id => _}} -> true
        _ -> false
      end
    end

    def fetch(source, batch_key, id) do
      with {:ok, batch} <- Map.fetch(source.results, batch_key) do
        case Map.fetch(batch, id) do
          :error -> {:error, "Unable to find id #{inspect(id)}"}
          {:ok, {:error, reason}} -> {:error, reason}
          {:ok, item} -> {:ok, item}
        end
      else
        :error ->
          {:error, "Unable to find batch #{inspect(batch_key)}"}
      end
    end

    def run(source) do
      fun = fn {batch_key, ids} ->
        {batch_key, source.load_function.(batch_key, ids)}
      end

      # TODO: Need to pass in a reference to async here.
      results = Dataloader.Async.tasks(Dataloader, source.batches, fun, source.opts)

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
