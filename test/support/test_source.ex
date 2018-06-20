defmodule Dataloader.TestSource do
  @moduledoc """
  This implements a simple `Source` that can be initialised with any function
  as it's `fun`, which it will then get called when `run/1` does. This should
  allow us to test `Dataloader.run/1`

  An example usage:

      ```elixir
      source = %Dataloader.TestSource{run: fn _ -> "HELLO" end}

      dataloader =
        Dataloader.new()
        |> Dataloader.add_source(:test, source)

      %{sources: sources} = Dataloader.run(dataloader)

      assert sources == %{test: "HELLO"}
      ```
  """

  defstruct run: nil, timeout: :timer.seconds(15), data: []

  defimpl Dataloader.Source do
    def load(source, _batch_key, _item_key), do: source

    def fetch(_source, _batch_key, _item_key), do: :error

    def pending_batches?(_source), do: true

    def put(source, _batch_key, _item_key, _item), do: source

    def run(source), do: source.run.(source)

    def timeout(source), do: source.timeout
  end
end
