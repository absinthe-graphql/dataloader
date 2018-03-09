defmodule Dataloader.Deferrable do
  defstruct evaluated?: false, value: nil, callback: nil, operations: [], dataloader: nil

  def new() do
    %__MODULE__{}
  end

  def add_operation(deferrable = %{operations: operations}, operation) do
    %{deferrable | operations: [operation | operations]}
  end

  defimpl Deferrable do
    defp apply_operations(dataloader, []), do: dataloader

    defp apply_operations(dataloader, [{operation, args} | operations]) do
      :erlang.apply(Dataloader, operation, [dataloader | args])
      |> apply_operations(operations)
    end

    def get_value(%Dataloader.Deferrable{value: value, evaluated?: true}), do: value

    defp run_callbacks(
           %Dataloader.Deferrable{operations: operations, callback: callback} = deferrable,
           dataloader,
           prev_deferrable
         ) do
      dataloader = apply_operations(dataloader, operations)

      if Dataloader.pending_batches?(dataloader) do
        %{deferrable | dataloader: dataloader}
      else
        run_callbacks(
          callback.(%{deferrable | dataloader: dataloader}),
          dataloader,
          deferrable
        )
      end
    end

    defp run_callbacks(other, dataloader, prev_deferrable) do
      %{
        prev_deferrable
        | value: other,
          dataloader: dataloader,
          evaluated?: true,
          callback: nil
      }
    end

    def evaluate_once(val, opts \\ [])

    def evaluate_once(val = %Dataloader.Deferrable{evaluated?: true}, _), do: val

    def evaluate_once(
          deferrable,
          opts
        ) do
      dataloader =
        opts[:dataloader]
        |> apply_operations(deferrable.operations)
        |> Dataloader.run()

      run_callbacks(deferrable, dataloader, opts[:prev])
    end

    def evaluate(val = %Dataloader.Deferrable{evaluated?: true}, opts), do: val

    def evaluate(val = %Dataloader.Deferrable{}, opts) do
      new_val = %{dataloader: dataloader} = evaluate_once(val, opts)

      opts =
        opts
        |> Keyword.put(:dataloader, dataloader)
        |> Keyword.put(:prev, val)

      evaluate(new_val, opts)
    end

    def then(val = %{callback: nil}, callback) do
      %{val | callback: callback}
    end

    def then(val = %{callback: previous_callback}, callback) do
      %Dataloader.Deferrable{
        val
        | callback: fn prev ->
            Defer.then(previous_callback.(prev), callback)
          end
      }
    end
  end
end