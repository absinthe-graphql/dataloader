# Contributing

Thank you for contributing to the project. We'd love to see your
issues and pull requests.

If you're creating a pull request, please consider these suggestions:

Fork, then clone the repo:

    git clone git@github.com:your-username/dataloader.git

Install the dependencies:

    mix deps.get

Make sure the tests pass.

Running tests for Dataloader requires a running instance of Postgres. The easiest way to do this is to run Postgres inside of Docker whilst running the Dataloader tests. In one terminal run:

    docker run -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=dataloader_test postgres

and in another terminal run:

    MIX_ENV=test mix ecto.setup
    mix test

If you kill the docker process, you will need to rerun the `ecto.setup` command as the data in the container is ephemeral (no mounted volumes are leveraged).

Make your change. Add tests for your change. Make the tests pass:

    mix test

Push to your fork (preferably to a non-`master` branch) and
[submit a pull request][pr].

[pr]: https://github.com/absinthe-graphql/dataloader/compare/

We'll review and answer your pull request as soon as possible. We may suggest
some changes, improvements, or alternatives. Let's work through it together.

Some things that will increase the chance that your pull request is accepted:

* Write tests.
* Include `@typedoc`s, `@spec`s, and `@doc`s
* Try to match the style conventions already present (and Elixir conventions,
  generally).
* Write a [good commit message][commit].

Thanks again for helping!

[commit]: http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html
