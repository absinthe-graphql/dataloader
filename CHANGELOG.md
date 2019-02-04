# Changelog

## v1.0.5 - 2019-02-03

- Bug Fix: Fix dialyzer spec for run_batch function

## v1.0.4 - 2018-09-14

- Bug Fix: Poor supervisor structure has been improved, which fixes large memory
  usage issues

## v1.0.3 - 2018-08-19

- Enhancement: Improved error handling when sources fail to load
  This provides two additional configurable methods of error handling (these
  options can be passed to `Dataloader.new/1`):

  * `:return_nil_on_error` - This is the previous default. Errors are logged,
  and values return `nil`.
  * `:raise_on_error` - this will raise a `Dataloader.GetError` when one
  of the `get` methods are called. This is now the default behaviour
  for handling errors
  * `:tuples` - this changes the `get/4`/`get_many/4` methods to return
  `:ok`/`:error` tuples instead of just the value. This frees up the
  caller to handle errors any way they see fit

- Enhancement: Improved caching characteristics on the KV source
- Enhancement: More flexible cardinality mapping for Ecto source
- Enhancement: Uniq the batched KV and Ecto values
- Bug Fix: When using the Ecto source it properly coerces all inputs for known
  fields.

Note: when upgrading it may be necessary to clear out your `_build` directory so
that the compiler picks up the protocol change.

### Breaking Changes

* Errors are raised instead of silently returning nil. See
  `:return_nil_on_error` option to keep the previous behavior.
* `Dataloader.get/4` will raise an error if you pass in an `item_key` that was
  not previously loaded. See
  https://github.com/absinthe-graphql/dataloader/issues/52 for discussion.

## v1.0.2 - 2018-04-10

- Enhancement: Custom batch functions for Ecto

## v1.0.1 - 2018-02-04

- Bug Fix: Ecto source properly caches results now.

## v1.0.0 - 2017-11-13

- Initial release
