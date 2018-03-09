defmodule Lazyloader.Deferrable do
  defstruct evaluated?: false, value: nil, callback: nil, operations: [], dataloader: nil

  def new() do
    %__MODULE__{}
  end

  def add_operation(deferrable = %{operations: operations}, operation) do
    %{deferrable | operations: [operation | operations]}
  end

  defp apply_operations(dataloader, %{operations: operations}),
    do: apply_operations(dataloader, operations)

  defp apply_operations(dataloader, []), do: dataloader

  defp apply_operations(dataloader, [
         %Lazyloader.Deferrable{operations: operations} | deferrables
       ]) do
    if !dataloader, do: raise("No dataloader supplied")

    dataloader
    |> apply_operations(operations)
    |> apply_operations(deferrables)
  end

  defp apply_operations(dataloader, [{operation, args} | operations]) do
    if !dataloader, do: raise("No dataloader supplied")

    :erlang.apply(Dataloader, operation, [dataloader | args])
    |> apply_operations(operations)
  end

  def get_value([], _), do: []

  def get_value([deferrable | deferrables], opts) do
    [get_value(deferrable, opts) | get_value(deferrables, opts)]
  end

  def get_value(%Lazyloader.Deferrable{value: value, evaluated?: true}, _opts) do
    value
  end

  defp run_callbacks([], _, []), do: []

  defp run_callbacks([deferrable | deferrables], dataloader, [prev_deferrable | prev_deferrables]) do
    deferrable = run_callbacks(deferrable, dataloader, prev_deferrable)
    if !deferrable.dataloader, do: raise("Oops no dataloader")

    [
      deferrable
      | run_callbacks(deferrables, deferrable.dataloader, prev_deferrables)
    ]
  end

  defp run_callbacks(
         %Lazyloader.Deferrable{callback: callback, evaluated?: false} = deferrable,
         dataloader,
         _prev_deferrable
       ) do
    dataloader = apply_operations(dataloader, deferrable)

    if Dataloader.pending_batches?(dataloader) do
      %{deferrable | dataloader: dataloader}
    else
      if !callback do
        raise "No callback found"
      end

      run_callbacks(
        callback.(%{deferrable | dataloader: dataloader}),
        dataloader,
        deferrable
      )
    end
  end

  defp run_callbacks(deferrable = %{evaluated?: true}, _, _), do: deferrable

  defp run_callbacks(other, dataloader, prev_deferrable) do
    %{
      prev_deferrable
      | value: other,
        dataloader: dataloader,
        evaluated?: true,
        callback: nil
    }
  end

  def execute(dataloader, deferrable) do
    dataloader |> apply_operations(deferrable) |> Dataloader.run()
  end

  def evaluate_once(val, opts \\ [])

  def evaluate_once(val = %Lazyloader.Deferrable{evaluated?: true}, _), do: val

  def evaluate_once(deferrables, opts) when is_list(deferrables) do
    dataloader = execute(opts[:dataloader], deferrables)

    if is_list(opts[:prev]) do
      run_callbacks(deferrables, dataloader, opts[:prev])
    else
      run_callbacks(deferrables, dataloader, Enum.map(deferrables, fn _ -> opts[:prev] end))
    end
  end

  def evaluate_once(
        deferrable,
        opts
      ) do
    dataloader = execute(opts[:dataloader], deferrable)

    run_callbacks(deferrable, dataloader, opts[:prev])
  end

  defp get_dataloader(%{dataloader: dataloader}), do: dataloader

  defp get_dataloader([%{dataloader: dataloader} | _]) do
    dataloader
  end

  defp all_evaluated?([]), do: true

  defp all_evaluated?([val | vals]) do
    val.evaluated? && all_evaluated?(vals)
  end

  defp do_evaluate(val, opts) do
    new_val = evaluate_once(val, opts)

    opts =
      opts
      |> Keyword.put(:dataloader, get_dataloader(new_val))
      |> Keyword.put(:prev, val)

    {new_val, opts}
  end

  def evaluate(val = %Lazyloader.Deferrable{evaluated?: true}, _opts), do: val

  def evaluate(val = %Lazyloader.Deferrable{}, opts) do
    {new_val, opts} = do_evaluate(val, opts)

    evaluate(new_val, opts)
  end

  def evaluate(vals, opts) when is_list(vals) do
    {new_vals, opts} = do_evaluate(vals, opts)

    if all_evaluated?(new_vals) do
      new_vals
    else
      evaluate(new_vals, opts)
    end
  end

  def then(val = %{callback: nil}, callback) do
    %{val | callback: callback}
  end

  def then(val = %{callback: previous_callback}, callback) do
    %Lazyloader.Deferrable{
      val
      | callback: fn prev ->
          Defer.then(previous_callback.(prev), callback)
        end
    }
  end

  ## --- implementantion functions
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