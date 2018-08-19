# Changelog

## v1.1.0 - Unreleased

- Enhancement: Improved error handling when sources fail to load
  This provides two additional configurable methods of error handling:

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
- Bug Fix: When using the Ecto source it properly coerces all inputs for known fields.
## v1.0.2 - 2018-04-10

- Enhancement: Custom batch functions for Ecto

## v1.0.1 - 2018-02-04

- Bug Fix: Ecto source properly caches results now.

## v1.0.0 - 2017-11-13

- Initial release
