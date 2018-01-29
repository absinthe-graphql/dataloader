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
end
