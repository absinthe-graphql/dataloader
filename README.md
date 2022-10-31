# Dataloader

[![Build Status](https://github.com/absinthe-graphql/dataloader/workflows/CI/badge.svg)](https://github.com/absinthe-graphql/dataloader/actions?query=workflow%3ACI)
[![Version](https://img.shields.io/hexpm/v/dataloader.svg)](https://hex.pm/packages/dataloader)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/dataloader/)
[![Download](https://img.shields.io/hexpm/dt/dataloader.svg)](https://hex.pm/packages/dataloader)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Last Updated](https://img.shields.io/github/last-commit/absinthe-graphql/dataloader.svg)](https://github.com/absinthe-graphql/dataloader/commits/master)

Dataloader provides an easy way efficiently load data in batches. It's inspired
by [https://github.com/facebook/dataloader](https://github.com/facebook/dataloader), although it makes some small API changes to better suit Elixir use cases.

## Installation

The package can be installed by adding [`:dataloader`](https://hex.pm/packages/dataloader) to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dataloader, "~> 1.0.0"}
  ]
end
```

Note: Dataloader requires Elixir 1.10 or higher.

## Upgrading

See [CHANGELOG](./CHANGELOG.md) for upgrade steps between versions.

## Documentation

- [Dataloader hexdocs](https://hexdocs.pm/dataloader).
- For the tutorial, guides, and general information about Absinthe-related
  projects, see [http://absinthe-graphql.org](http://absinthe-graphql.org).

## Usage

Central to Dataloader is the idea of a source. A single Dataloader struct can
have many different sources, which represent different ways to load data.

Here's an example of a data loader using an Ecto source, and then loading some
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

### Sources

Dataloader ships with two different built in sources. The first is the Ecto source for easily pulling out data with ecto. The other is a simple `KV` key value source. See each module for its respective documentation.

Anything that implements the `Dataloader.Source` protocol can act as a source.

## Community

The project is under constant improvement by a growing list of
contributors, and your feedback is important. Please join us in Slack
(`#absinthe-graphql` under the Elixir Slack account) or the Elixir Forum
(tagged `absinthe`).

Please remember that all interactions in our official spaces follow
our [Code of Conduct](./CODE_OF_CONDUCT.md).

## Related Projects

See the [GitHub organization](https://github.com/absinthe-graphql).

## Contributing

Please follow [contribution guide](./CONTRIBUTING.md).

## License

See [LICENSE.md](./LICENSE.md).
