defprotocol DataLoader.Source do
  @type t :: module

  @type batch_key :: term
  @type item_key :: term

  @spec add(t, batch_key, item_key, Keyword.t) :: t
  def add(source, batch_key, item_key, opts)

  @spec run(t) :: t
  def run(source)

  @spec get_result(t, batch_key, item_key) :: term
  def get_result(source, batch_key, item_key)

  @spec pending_batches?(t) :: boolean
  def pending_batches?(source)
end
