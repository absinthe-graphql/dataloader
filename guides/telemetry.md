# Telemetry

Dataloader uses `telemetry` to instrument its activity.

Call `:telemetry.attach/4` or `:telemetry.attach_many/4` to attach your
handler function to any of the following event names:

- `[:dataloader, :batches, :run, :start]` when the dataloader processing starts
- `[:dataloader, :batches, :run, :stop]` when the dataloader processing finishes
- `[:dataloader, :source, :batch, :run, :start]` when the dataloader starts processing a single batch
- `[:dataloader, :source, :batch, :run, :stop]` when the dataloader finishes processing a single batch

Telemetry handlers are called with `measurements` and `metadata`. For details on
what is passed, checkout `Dataloader`.

## Interactive Telemetry

As an example, you could attach a handler in an `iex -S mix` shell. Paste in:

```elixir
:telemetry.attach_many(
  :demo,
  [
    [:dataloader, :batches, :run, :stop]
  ],
  fn event_name, measurements, metadata, _config ->
    %{
      event_name: event_name,
      measurements: measurements,
      metadata: metadata
    }
    |> IO.inspect()
  end,
  []
)
```

After a query is executed, you'll see something like:

```elixir
%{
  event_name: [:dataloader, :batches, :run, :stop],
  measurements: %{duration: 112151},
  metadata: %{
    dataloader: %Dataloader{
      options: [get_policy: :raise_on_error],
      sources: ...
    },
    id: -576460752303420441
  }
}
```
