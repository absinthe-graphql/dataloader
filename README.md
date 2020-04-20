# Dataloader

Dataloader provides an easy way efficiently load data in batches. It's inspired
by https://github.com/facebook/dataloader, although it makes some small API
changes to better suit Elixir use cases.

## Installation

The package can be installed by adding [`dataloader`](https://hex.pm/packages/dataloader) to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dataloader, "~> 1.0.0"}
  ]
end
```

## Usage

Central to Dataloader is the idea of a source. A single Dataloader struct can
have many different sources, which represent different ways to load data.

Here's an example of a data loader using an ecto source, and then loading some
organization data.

```elixir
source = Dataloader.Ecto.new(MyApp.Repo)

# setup the loader
loader = Dataloader.new |> Dataloader.add_source(:db, source)

# load some things
loader =
  loader
  |> Dataloader.load(:db, Organization, 1)
  |> Dataloader.load_many(:db, Organization, [4, 9])

# actually retrieve them
loader = Dataloader.run(loader)

# Now we can get whatever values out we want
organizations = Dataloader.get_many(loader, :db, Organization, [1,4])
```

This will do a single SQL query to get all organizations by ids 1, 4, and 9. You
can load multiple batches from multiple sources, and then when `run/1` is called
batch will be loaded concurrently.

Here we named the source `:db` within our dataloader. More commonly though if
you're using Phoenix you'll want to name it after one of your contexts, and have
a different source used for each context. This provides an easy way to enforce
data access rules within each context. See the `Dataloader.Ecto` moduledocs for
more details

## Sources

Dataloader ships with two different built in sources. The first is the Ecto source for easily pulling out data with ecto. The other is a simple `KV` key value source. See each module for its respective documentation.

Anything that implements the `Dataloader.Source` protocol can act as a source.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc). The docs can be found at [https://hexdocs.pm/dataloader](https://hexdocs.pm/dataloader).

## Contributing

Running tests for Dataloader requires a running instance of Postgres. The easiest way to do this is to run Postgres inside of Docker whilst running the Dataloader tests. In one terminal run:

```terminal
$ docker run -p 5432:5432 postgres
```

and in another terminal run:

```terminal
$ MIX_ENV=test mix ecto.setup
$ mix test
```

If you kill the docker process, you will need to rerun the `ecto.setup` command as the data in the container is ephemeral (no mounted volumes are leveraged).
