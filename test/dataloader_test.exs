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

  test "that already added sources can be identified" do
    source = Dataloader.KV.new(fn _, ids -> Enum.with_index(ids) end)

    loader =
      Dataloader.new
      |> Dataloader.add_source(:foo, source)

    assert Dataloader.has_source?(loader, :foo)
  end
end
