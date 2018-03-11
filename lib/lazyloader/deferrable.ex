defmodule Lazyloader.Deferrable do
  defstruct evaluated?: false, value: nil, callback: nil, operations: [], dataloader: nil

  def new() do
    %__MODULE__{}
  end

  def add_operation(deferrable = %{operations: operations}, operation) do
    %{deferrable | operations: [operation | operations]}
  end

  def commit_operations(dataloader, %{operations: operations}),
    do: commit_operations(dataloader, operations)

  def commit_operations(dataloader, []), do: dataloader

  def commit_operations(dataloader, deferrables = [%__MODULE__{} | _]) do
    Enum.reduce(deferrables, dataloader, &commit_operations(&2, &1))
  end

  def commit_operations(dataloader, [{operation, args} | operations]) do
    if !dataloader, do: raise("No dataloader supplied")

    :erlang.apply(Dataloader, operation, [dataloader | args])
    |> commit_operations(operations)
  end

  def get_value([], _), do: []

  def get_value(deferrables, opts) when is_list(deferrables) do
    Enum.map(deferrables, &get_value(&1, opts))
  end

  def get_value(%__MODULE__{value: value, evaluated?: true}, _opts) do
    value
  end

  defp run_callbacks(
         %__MODULE__{callback: callback, evaluated?: false} = deferrable,
         dataloader
       ) do
    dataloader = commit_operations(dataloader, deferrable)
    deferrable = %{deferrable | dataloader: dataloader}

    if Dataloader.pending_batches?(dataloader) do
      deferrable
    else
      if !callback, do: raise("No callback found")

      run_callbacks(
        callback.(deferrable),
        dataloader
      )
    end
  end

  defp run_callbacks(deferrables, dataloader) when is_list(deferrables) do
    Enum.map(deferrables, &run_callbacks(&1, dataloader))
  end

  defp run_callbacks(deferrable = %{evaluated?: true}, _), do: deferrable

  defp run_callbacks(other, dataloader) do
    %__MODULE__{
      value: other,
      dataloader: dataloader,
      evaluated?: true,
      callback: nil
    }
  end

  def evaluate_once(val, opts \\ [])

  def evaluate_once(val = %__MODULE__{evaluated?: true}, _), do: val

  def evaluate_once(
        deferrable,
        opts
      ) do
    run_dataloader = Keyword.get(opts, :run_dataloader, true)
    dataloader = opts[:dataloader]
    if(!dataloader, do: raise("No dataloader found"))

    dataloader = commit_operations(dataloader, deferrable)
    dataloader = if(run_dataloader, do: Dataloader.run(dataloader), else: dataloader)

    run_callbacks(deferrable, dataloader)
  end

  defp all_evaluated?([]), do: true

  defp all_evaluated?([val | vals]) do
    val.evaluated? && all_evaluated?(vals)
  end

  defp add_new_dataloader(opts, %__MODULE__{dataloader: dataloader}) do
    Keyword.put(opts, :dataloader, dataloader)
  end

  defp add_new_dataloader(opts, [%__MODULE__{dataloader: dataloader} | _]) do
    Keyword.put(opts, :dataloader, dataloader)
  end

  def evaluate(val = %__MODULE__{evaluated?: true}, _opts), do: val

  def evaluate(val = %__MODULE__{}, opts) do
    if !opts[:dataloader], do: raise("No dataloader found!")

    val = evaluate_once(val, opts)
    evaluate(val, add_new_dataloader(opts, val))
  end

  def evaluate(vals, opts) when is_list(vals) do
    new_vals = evaluate_once(vals, opts)
    if !opts[:dataloader], do: raise("No dataloader found!")

    if all_evaluated?(new_vals) do
      new_vals
    else
      evaluate(new_vals, add_new_dataloader(opts, vals))
    end
  end

  def then(val = %{callback: nil}, callback) do
    %{val | callback: callback}
  end

  def then(val = %{callback: previous_callback}, callback) do
    %__MODULE__{
      val
      | callback: fn prev ->
          Defer.then(previous_callback.(prev), callback)
        end
    }
  end

  ## --- Deferrable implementation functions
  defimpl Deferrable do
    def evaluate(deferrable, opts \\ []) do
      Lazyloader.Deferrable.evaluate(deferrable, opts)
    end

    def evaluate_once(deferrable, opts \\ []) do
      Lazyloader.Deferrable.evaluate_once(deferrable, opts)
    end

    def get_value(deferrable, opts \\ []) do
      Lazyloader.Deferrable.get_value(deferrable, opts)
    end

    def then(deferrable, callback) do
      Lazyloader.Deferrable.then(deferrable, callback)
    end
  end
end