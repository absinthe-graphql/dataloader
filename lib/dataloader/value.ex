defmodule Dataloader.Value do
  @type t :: %__MODULE__{
          dataloader: %Dataloader{},
          callback: (DataLoader.t() -> any) | nil,
          lazy?: boolean,
          value: any
        }
  defstruct dataloader: nil, callback: nil, lazy?: true, value: nil
end