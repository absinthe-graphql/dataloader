defprotocol DataLoader.Source do
  @type t :: module

  @type batch_key :: term
  @type item_key :: term
  @type item :: term

  @spec add(t, batch_key, item_key, item) :: t
  def add(source, batch_key, item_key, item)

  @spec run(t) :: t
  def run(source)

  @spec get_result(t, batch_key, item_key) :: item
  def get_result(source, batch_key, item_key)
end
