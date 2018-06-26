defmodule DataloaderTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  test "pmap won't die if an exception in a child happens" do
    log =
      capture_log(fn ->
        assert %{2 => 4} ==
                 Dataloader.pmap(
                   [1, 2],
                   fn
                     1 -> raise "boom"
                     2 -> {2, 4}
                   end,
                   []
                 )
      end)

    assert log =~ "boom"
  end

  test "fails silently and returns an empty map of sources if things timeout" do
    source = %Dataloader.TestSource{}

    dataloader =
      Dataloader.new(timeout: 1) # Note the short timeout
      |> Dataloader.add_source(:test, source)

    new_dataloader = Dataloader.run(dataloader)

    assert dataloader == new_dataloader
  end
end
