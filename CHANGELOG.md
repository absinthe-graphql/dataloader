# Changelog

## v2.0.0 2023-07-24

- Breaking Feature: Automatically handle sync vs async for the ecto dataloader source ([#146](https://github.com/absinthe-graphql/dataloader/pull/146)). Other dataloader source implementations need to add an `async?` function to comply with the protocol. NOTE: This only impacts you if  you have a custom dataloader source. If you use the built in Ecto or KV sources then there is nothing you need to do.
- Improvement: KV source no longer double wraps results in `{:ok, {:ok, value}} tuples` when you return an OK tuple while using the tuple policy ([#145](https://github.com/absinthe-graphql/dataloader/pull/145))

## v1

For v1 changes see https://github.com/absinthe-graphql/dataloader/blob/v1/CHANGELOG.md
