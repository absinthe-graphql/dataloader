[
  inputs: ["mix.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:defer],
  locals_without_parens: [defer: 2, await: 1]
]
