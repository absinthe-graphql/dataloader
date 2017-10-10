defprotocol DataLoader.Source do
  @type t :: module

  @type batch_key :: term
  @type item_key :: term

  @spec load(t, batch_key, item_key) :: t
  def load(source, batch_key, item_key)

  @spec run(t) :: t
  def run(source)

  @spec get(t, batch_key, item_key) :: term
  def get(source, batch_key, item_key)

  @spec pending_batches?(t) :: boolean
  def pending_batches?(source)
end
