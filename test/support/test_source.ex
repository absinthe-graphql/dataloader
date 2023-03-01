defmodule Dataloader.TestSource do
  defmodule Behaviour do
    @callback load(
                Dataloader.Source.t(),
                Dataloader.Source.batch_key(),
                Dataloader.Source.item_key()
              ) :: Dataloader.Source.t()
    @callback run(Dataloader.Source.t()) :: Dataloader.Source.t()
    @callback fetch(
                Dataloader.Source.t(),
                Dataloader.Source.batch_key(),
                Dataloader.Source.item_key()
              ) :: {:ok, term} | {:error, term}
    @callback pending_batches?(Dataloader.Source.t()) :: boolean
    @callback put(
                Dataloader.Source.t(),
                Dataloader.Source.batch_key(),
                Dataloader.Source.item_key(),
                term
              ) :: Dataloader.Source.t()
    @callback timeout(Dataloader.Source.t()) :: number
  end

  defmodule SourceImpl do
    defstruct [:name]

    defimpl Dataloader.Source do
      def load(source, batch_key, item_key) do
        Application.get_env(:dataloader, :source_mock).load(source, batch_key, item_key)
      end

      def run(source) do
        Application.get_env(:dataloader, :source_mock).run(source)
      end

      def fetch(source, batch_key, item_key) do
        Application.get_env(:dataloader, :source_mock).fetch(source, batch_key, item_key)
      end

      def pending_batches?(source) do
        Application.get_env(:dataloader, :source_mock).pending_batches?(source)
      end

      def put(source, batch_key, item_key, value) do
        Application.get_env(:dataloader, :source_mock).put(source, batch_key, item_key, value)
      end

      def timeout(source) do
        Application.get_env(:dataloader, :source_mock).timeout(source)
      end
    end
  end
end
