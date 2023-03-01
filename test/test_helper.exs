{:ok, _} = Dataloader.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Dataloader.TestRepo, :manual)
Mox.defmock(Dataloader.TestSource.MockSource, for: Dataloader.TestSource.Behaviour)

ExUnit.start()
