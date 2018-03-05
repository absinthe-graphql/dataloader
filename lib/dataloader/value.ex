defmodule Dataloader.Value do
  @type t :: %__MODULE__{
          dataloader: %Dataloader{},
          callback: (Dataloader.t() -> any) | nil,
          chained_callbacks: [(any, Dataloader.t() -> any)],
          lazy?: boolean,
          value: any
        }
  defstruct dataloader: nil, callback: nil, chained_callbacks: [], lazy?: true, value: nil
end