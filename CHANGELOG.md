# Changelog

## v2.0.0-dev (unreleased)

- Breaking Feature: Automatically handle sync vs async for the ecto dataloader source ([#146](https://github.com/absinthe-graphql/dataloader/pull/146)). Other dataloader source implementations need to add an `async?` function to comply with the protocol.
- Improvement: KV source no longer double wraps results in `{:ok, {:ok, value}} tuples` when you return an OK tuple while using the tuple policy ([#145](https://github.com/absinthe-graphql/dataloader/pull/145))

## v1

For v1 changes see https://github.com/absinthe-graphql/dataloader/blob/v1/CHANGELOG.md
