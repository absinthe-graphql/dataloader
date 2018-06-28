defmodule DataloaderTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  describe "run/1" do
    test "returns an ok tuple on success" do
      source = %Dataloader.TestSource{
        run: fn _source ->
          function_that_succeeds = fn
            1 -> "hello"
            2 -> "bye"
          end

          Dataloader.pmap([1, 2], function_that_succeeds)
        end
      }

      dataloader =
        Dataloader.new()
        |> Dataloader.add_source(:test, source)

      %{sources: sources} = Dataloader.run(dataloader)

      assert %{test: %{1 => {:ok, "hello"}, 2 => {:ok, "bye"}}} = sources
    end

    test "returns an error tuple on failure" do
      source = %Dataloader.TestSource{
        run: fn _source ->
          function_that_raises = fn :this_will_raise -> raise "hell" end
          Dataloader.pmap([:this_will_raise], function_that_raises)
        end
      }

      dataloader =
        Dataloader.new()
        |> Dataloader.add_source(:test, source)

      log =
        capture_log(fn ->
          %{sources: sources} = Dataloader.run(dataloader)

          assert %{test: %{this_will_raise: {:error, error}}} = sources

          assert inspect(error) =~ ~s(%RuntimeError{message: "hell"})
        end)

      assert log =~ "hell"
    end

    test "returns an error if the source times out" do
      source = %Dataloader.TestSource{
        run: fn _source ->
          function_that_times_out = fn :this_will_timeout -> Process.sleep(:timer.seconds(5)) end
          Dataloader.pmap([:this_will_timeout], function_that_times_out, timeout: 1)
        end
      }

      dataloader =
        Dataloader.new()
        |> Dataloader.add_source(:test, source)

      %{sources: sources} = Dataloader.run(dataloader)

      assert %{test: %{this_will_timeout: {:error, :timeout}}} = sources
    end
  end
end
