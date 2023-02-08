# Telemetry

Dataloader uses `telemetry` to instrument its activity.

Call `:telemetry.attach/4` or `:telemetry.attach_many/4` to attach your
handler function to any of the following event names:

- `[:dataloader, :source, :run, :start]` when the dataloader processing starts
- `[:dataloader, :source, :run, :stop]` when the dataloader processing finishes
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
    [:dataloader, :source, :run, :stop]
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
  event_name: [:dataloader, :source, :run, :stop],
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

## Opentelemetry

When using Opentelemetry, one usually wants to correlate spans that are created
in spawned tasks with the main trace. For example, you might have a trace started
in a Phoenix endpoint, and then have spans around database access.

One can correlate manually by attaching the OTel context the task function:

```elixir
ctx = OpenTelemetry.Ctx.get_current()

Task.async(fn ->
  OpenTelemetry.Ctx.attach(ctx)

  # do stuff that might create spans
end)
```

When using Dataloader, the tasks are spawned by the loader itself, so you can't
attach the context manually.

Instead, you can add the `:opentelemetry_process_propagator` package to your
dependencies, which has suitable wrappers that will attach the context
automatically. If the package is installed, Dataloader will use it in place
of the default `Task.async/1` and `Task.async_stream/3`.
