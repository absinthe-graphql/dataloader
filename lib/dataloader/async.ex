defprotocol Dataloader.Task do
  @fallback_to_any true

  def await(x, task, timeout)
  def async(x, f)
  def async_stream(x, xs, f, opts)
  def timeout(x)
end

defimpl Dataloader.Task, for: Any do
  def await(_, task, timeout), do: Task.await(task, timeout)
  def async(_, f), do: Task.async(f)
  def async_stream(_, xs, f, opts), do: Task.async_stream(xs, f, opts)
  def timeout(_), do: Dataloader.default_timeout()
end

defimpl Dataloader.Task, for: Dataloader do
  def await(d, task, timeout), do: d.task.await(task, timeout)
  def async(d, f), do: d.task.async(f)
  def async_stream(d, xs, f, opts), do: d.task.async_stream(xs, f, opts)
  def timeout(d), do: Dataloader.timeout(d)
end

defmodule Dataloader.Async do
  @doc """
  This is a helper method to run a set of async tasks in such a way that if
  one of the tasks crashing will not crash the caller spawning them. Instead,
  crashes will be rewritten to {:error, reason}.

  This leverages the fact that Task.async_stream/3 will return {:exit, reason}
  for any tasks that crash during execution as long as the calling process
  it trappings exits. In order to avoid changing Process flags on the caller,
  we spawn an intermediary task which we set to trap exits, and then call
  Task.async_stream/3 from the spawned task.

  See `run_task/3` for an example of a `fun` implementation, this will return
  whatever that returns.
  """
  @spec tasks(module(), atom(), list()) :: any()
  def tasks(async, xs, fun, opts \\ []) do
    task_opts =
      opts
      |> Keyword.take([:timeout, :max_concurrency])
      |> Keyword.put_new(:timeout, Dataloader.Task.timeout(async))
      |> Keyword.put(:on_timeout, :kill_task)

    task =
      Dataloader.Task.async(async, fn ->
        # The purpose of `:trap_exit` here is so that we can ensure that any failures
        # within the tasks do not kill the current process. We want to get results
        # back no matter what.
        Process.flag(:trap_exit, true)

        Dataloader.Task.async_stream(async, xs, fun, task_opts)
        |> Enum.map(fn
          {:ok, result} -> {:ok, result}
          {:exit, reason} -> {:error, reason}
        end)
      end)

    res = Dataloader.Task.await(async, task, :infinity)
    Enum.zip(xs, res) |> Map.new()
  end
end
