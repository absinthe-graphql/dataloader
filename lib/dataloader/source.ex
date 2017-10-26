defprotocol Dataloader.Source do
  @type batch_key :: term
  @type item_key :: term

  @spec load(t, batch_key, item_key) :: t
  def load(source, batch_key, item_key)

  @spec run(t) :: t
  def run(source)

  @spec fetch(t, batch_key, item_key) :: {:ok, term} | :error
  def fetch(source, batch_key, item_key)

  @spec pending_batches?(t) :: boolean
  def pending_batches?(source)
end
