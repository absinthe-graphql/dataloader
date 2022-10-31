defprotocol Dataloader.Source do
  @type batch_key :: term
  @type item_key :: term

  @doc """
  Enqueue an item to be loaded under a given batch
  """
  @spec load(t, batch_key, item_key) :: t
  def load(source, batch_key, item_key)

  @doc """
  Run any batches queued up for this source.
  """
  @spec run(t) :: t
  def run(source)

  @doc """
  Fetch the result found under the given batch and item keys.
  """
  @spec fetch(t, batch_key, item_key) :: {:ok, term} | {:error, term}
  def fetch(source, batch_key, item_key)

  @doc """
  Determine if there are any batches that have not yet been run.
  """
  @spec pending_batches?(t) :: boolean
  def pending_batches?(source)

  @doc """
  Put a value into the results.

  Useful for warming caches. The source is permitted to reject the value.
  """
  @spec put(t, batch_key, item_key, term) :: t
  def put(source, batch_key, item_key, item)

  @doc """
  Returns the timeout (in ms) for the source.

  This is important for ensuring the dataloader obeys the timeouts when running
  multiple sources concurrently
  """
  @spec timeout(t) :: number
  def timeout(source)
end
