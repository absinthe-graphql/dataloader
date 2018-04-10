defmodule Lazyloader.Deferrable do
  defstruct then: nil, operations: [], dataloader: nil

  def new() do
    %__MODULE__{}
  end

  def add_operation(deferrable = %{operations: operations}, operation) do
    %{deferrable | operations: [operation | operations]}
  end

  def commit_operations(dataloader, operations)

  def commit_operations(dataloader, %{operations: operations}),
    do: commit_operations(dataloader, operations)

  def commit_operations(dataloader, []), do: dataloader

  def commit_operations(dataloader, [{operation, args} | operations]) do
    if !dataloader, do: raise("No dataloader supplied")

    :erlang.apply(Dataloader, operation, [dataloader | args])
    |> commit_operations(operations)
  end

  def commit_operations(dataloader, [deferrable | deferrables]) when is_list(deferrables) do
    commit_operations(dataloader, deferrable)
    |> commit_operations(deferrables)
  end

  def commit_operations(dataloader, _), do: dataloader

  defp run_callbacks(
         %__MODULE__{then: nil},
         _
       ),
       do: raise("No callback found")

  defp run_callbacks(
         %__MODULE__{then: then} = deferrable,
         dataloader
       ) do
    dataloader = commit_operations(dataloader, deferrable)

    if Dataloader.pending_batches?(dataloader) do
      deferrable
    else
      run_callbacks(
        then.(%{deferrable | dataloader: dataloader}),
        dataloader
      )
    end
  end

  defp run_callbacks(deferrables, dataloader) when is_list(deferrables) do
    Enum.map(deferrables, &run_callbacks(&1, dataloader))
  end

  defp run_callbacks(other, _) do
    other
  end

  def run_once(val, context \\ [])

  def run_once(
        deferrable,
        context
      ) do
    run_dataloader = Keyword.get(context, :run_dataloader, true)
    if(!context[:dataloader], do: raise("No dataloader found"))

    dataloader = commit_operations(context[:dataloader], deferrable)
    dataloader = if(run_dataloader, do: Dataloader.run(dataloader), else: dataloader)
    context = Keyword.put(context, :dataloader, dataloader)
    result = run_callbacks(deferrable, dataloader)
    {result, context}
  end

  def run(val = %__MODULE__{}, context) do
    if !context[:dataloader], do: raise("No dataloader found in context!")

    {val, context} = Deferrable.run_once(val, context)

    Deferrable.run(val, context)
  end

  def run(vals, context) when is_list(vals) do
    {new_vals, context} = Deferrable.run_once(vals, context)
    if !context[:dataloader], do: raise("No dataloader found in context!")

    if not Deferrable.deferrable?(new_vals) do
      {new_vals, context}
    else
      Deferrable.run(new_vals, context)
    end
  end

  def then(val, callback)

  def then(val = %{then: nil}, callback) do
    %{val | then: callback}
  end

  def then(val = %{then: then}, callback) do
    %__MODULE__{
      val
      | then: fn prev ->
          Deferrable.then(then.(prev), callback)
        end
    }
  end

  ## --- Deferrable implementation functions
  defimpl Deferrable do
    def run(deferrable, opts \\ []) do
      Lazyloader.Deferrable.run(deferrable, opts)
    end

    def run_once(deferrable, opts \\ []) do
      Lazyloader.Deferrable.run_once(deferrable, opts)
    end

    def then(deferrable, callback) do
      Lazyloader.Deferrable.then(deferrable, callback)
    end

    def deferrable?(_), do: true
  end
end
