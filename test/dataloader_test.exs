defmodule DataloaderTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mox

  doctest Dataloader

  @data [
    users: [
      [id: "ben", username: "Ben Wilson"],
      [id: "bruce", username: "Bruce Williams"]
    ]
  ]

  defp query(batch_key, ids = %MapSet{}) do
    for id <- ids, into: %{} do
      query(batch_key, id)
    end
  end

  defp query(_batch_key, "explode"), do: raise("hell")

  defp query(batch_key, id) do
    item =
      @data[batch_key]
      |> Enum.find(fn data -> data[:id] == id end)

    {id, item}
  end

  setup :verify_on_exit!

  setup do
    loader =
      Dataloader.new()
      |> Dataloader.add_source(:test, Dataloader.KV.new(&query(&1, &2)))

    [loader: loader]
  end

  describe "setting defaults" do
    test "new/1 sets an appropriate default get_policy" do
      loader = Dataloader.new()

      assert loader.options[:get_policy] == :raise_on_error

      loader = Dataloader.new(other: :option)

      assert loader.options[:get_policy] == :raise_on_error
    end

    test "new/1 can override the default policy" do
      loader = Dataloader.new(get_policy: :foo)

      assert loader.options[:get_policy] == :foo
    end
  end

  describe "async?: false" do
    test "runs tasks in the same process" do
      query = fn _batch_key, ids = %MapSet{} ->
        for id <- ids, into: %{} do
          {id, self()}
        end
      end

      loader =
        Dataloader.new(async?: false)
        |> Dataloader.add_source(:sync, Dataloader.KV.new(query, async?: false))
        |> Dataloader.add_source(:async, Dataloader.KV.new(query))

      result =
        loader
        |> Dataloader.load(:sync, :users, :sync)
        |> Dataloader.load(:async, :users, :async)
        |> Dataloader.run()

      assert Dataloader.get(result, :sync, :users, :sync) == self()
      assert Dataloader.get(result, :async, :users, :async) != self()
    end
  end

  describe "unknown sources" do
    test "load/3 for unknown source returns error", %{loader: loader} do
      assert_raise RuntimeError, ~r/Source does not exist/, fn ->
        loader |> Dataloader.load(:bogus, :users, "ben")
      end
    end

    test "get/3 for unknown source returns error", %{loader: loader} do
      assert_raise RuntimeError, ~r/Source does not exist/, fn ->
        loader
        |> Dataloader.load(:test, :users, "ben")
        |> Dataloader.run()
        |> Dataloader.get(:bogus, :users, "ben")
      end
    end
  end

  describe "run/1" do
    test "exceeds timeout" do
      Dataloader.TestSource.MockSource
      # lowest possible timeout
      |> expect(:timeout, fn _ -> 1 end)
      # false would skip invoking Source.run/1
      |> expect(:pending_batches?, fn _ -> true end)
      # Dataloader adds one second to every timeout, to trigger timeout we
      # need to hold longer than <timeout> + 1s
      |> expect(:run, fn _ -> Process.sleep(2) end)

      loader =
        Dataloader.new(get_policy: :tuples, async?: true, timeout_margin: 0)
        |> Dataloader.add_source(:test, %Dataloader.TestSource.SourceImpl{})
        |> Dataloader.run()

      # Dataloader replaces the source struct with error tuple. There is
      # reasonable recovery from timeout.
      assert %{sources: %{test: {:error, :timeout}}} = loader
      # put changes nothing
      assert ^loader = Dataloader.put(loader, :test, :foo, :bar, :baz)
      # load changes nothing
      assert ^loader = Dataloader.load(loader, :test, :foo, :bar)
      # get returns the error, nil or raises a GetError
      assert {:error, :timeout} == Dataloader.get(loader, :test, :foo, :bar)
    end

    test "use highest timeout plus margin as timeout for all tasks" do
      Dataloader.TestSource.MockSource
      |> expect(:timeout, 2, fn %{timeout: t} -> t end)
      # pending_batches? is only checked for any?
      |> expect(:pending_batches?, fn _ -> true end)
      # Sleep for 2ms (not triggering timeout) or 11ms (triggering timeout)
      |> expect(:run, 2, fn s ->
        Process.sleep(s.timeout + 1)
        s
      end)

      loader =
        Dataloader.new(get_policy: :tuples, async?: true, timeout_margin: 0)
        |> Dataloader.add_source(:test_1, %Dataloader.TestSource.SourceImpl{timeout: 1})
        |> Dataloader.add_source(:test_10, %Dataloader.TestSource.SourceImpl{timeout: 10})
        |> Dataloader.run()

      assert %{sources: %{test_1: %{}, test_10: {:error, :timeout}}} = loader
    end
  end

  describe "get methods when configured to raise an error" do
    test "get/4 returns a value when successful", %{loader: loader} do
      result =
        loader
        |> Dataloader.load(:test, :users, "ben")
        |> Dataloader.run()
        |> Dataloader.get(:test, :users, "ben")

      assert result == [id: "ben", username: "Ben Wilson"]
    end

    test "get_many/4 returns a value when successful and should emit telemetry events", %{
      loader: loader,
      test: test
    } do
      self = self()

      :ok =
        :telemetry.attach_many(
          "#{test}",
          [
            [:dataloader, :source, :run, :start],
            [:dataloader, :source, :run, :stop]
          ],
          fn name, measurements, metadata, _ ->
            send(self, {:telemetry_event, name, measurements, metadata})
          end,
          nil
        )

      result =
        loader
        |> Dataloader.load_many(:test, :users, ["ben", "bruce"])
        |> Dataloader.run()
        |> Dataloader.get_many(:test, :users, ["ben", "bruce"])

      assert_receive {:telemetry_event, [:dataloader, :source, :run, :start], %{system_time: _},
                      %{id: _, dataloader: _}}

      assert_receive {:telemetry_event, [:dataloader, :source, :run, :stop], %{duration: _},
                      %{id: _, dataloader: _}}

      assert result == [
               [id: "ben", username: "Ben Wilson"],
               [id: "bruce", username: "Bruce Williams"]
             ]
    end

    test "get/4 raises an exception when there was an error loading the data", %{loader: loader} do
      log =
        capture_log(fn ->
          loader =
            loader
            |> Dataloader.load(:test, :users, "explode")
            |> Dataloader.run()

          assert_raise Dataloader.GetError, ~r/hell/, fn ->
            loader
            |> Dataloader.get(:test, :users, "explode")
          end
        end)

      assert log =~ "hell"
    end

    test "get_many/4 raises an exception when there was an error loading the data", %{
      loader: loader
    } do
      log =
        capture_log(fn ->
          loader =
            loader
            |> Dataloader.load_many(:test, :users, ["explode"])
            |> Dataloader.run()

          assert_raise Dataloader.GetError, ~r/hell/, fn ->
            loader
            |> Dataloader.get_many(:test, :users, ["explode"])
          end
        end)

      assert log =~ "hell"
    end
  end

  describe "get methods when configured to return `nil` on error" do
    setup %{loader: loader} do
      [loader: %{loader | options: [get_policy: :return_nil_on_error]}]
    end

    test "get/4 returns a value when successful", %{loader: loader} do
      result =
        loader
        |> Dataloader.load(:test, :users, "ben")
        |> Dataloader.run()
        |> Dataloader.get(:test, :users, "ben")

      assert result == [id: "ben", username: "Ben Wilson"]
    end

    test "get_many/4 returns values when successful", %{loader: loader} do
      result =
        loader
        |> Dataloader.load_many(:test, :users, ["ben", "bruce"])
        |> Dataloader.run()
        |> Dataloader.get_many(:test, :users, ["ben", "bruce"])

      assert result == [
               [id: "ben", username: "Ben Wilson"],
               [id: "bruce", username: "Bruce Williams"]
             ]
    end

    test "get/4 logs the exception and returns `nil` when there was an error loading the data", %{
      loader: loader
    } do
      log =
        capture_log(fn ->
          result =
            loader
            |> Dataloader.load(:test, :users, "explode")
            |> Dataloader.run()
            |> Dataloader.get(:test, :users, "explode")

          assert result |> is_nil()
        end)

      assert log =~ "hell"
    end

    test "get_many/4 logs the exception and returns `nil` when there was an error loading the data",
         %{loader: loader} do
      log =
        capture_log(fn ->
          result =
            loader
            |> Dataloader.load_many(:test, :users, ["ben", "explode"])
            |> Dataloader.run()
            |> Dataloader.get_many(:test, :users, ["ben", "explode"])

          assert result == [nil, nil]
        end)

      assert log =~ "hell"
    end
  end

  describe "get methods when configured to return ok/error tuples" do
    setup %{loader: loader} do
      [loader: %{loader | options: [get_policy: :tuples]}]
    end

    test "get/4 returns an {:ok, value} tuple when successful", %{loader: loader} do
      result =
        loader
        |> Dataloader.load(:test, :users, "ben")
        |> Dataloader.run()
        |> Dataloader.get(:test, :users, "ben")

      assert result == {:ok, [id: "ben", username: "Ben Wilson"]}
    end

    test "get_many/4 returns a list of {:ok, value} tuples when successful", %{loader: loader} do
      result =
        loader
        |> Dataloader.load_many(:test, :users, ["ben", "bruce"])
        |> Dataloader.run()
        |> Dataloader.get_many(:test, :users, ["ben", "bruce"])

      assert result == [
               {:ok, [id: "ben", username: "Ben Wilson"]},
               {:ok, [id: "bruce", username: "Bruce Williams"]}
             ]
    end

    test "get/4 returns an {:error, reason} tuple when there was an error loading the data", %{
      loader: loader
    } do
      log =
        capture_log(fn ->
          result =
            loader
            |> Dataloader.load(:test, :users, "explode")
            |> Dataloader.run()
            |> Dataloader.get(:test, :users, "explode")

          assert {:error, {%RuntimeError{message: "hell"}, _stacktrace}} = result
        end)

      assert log =~ "hell"
    end

    test "get_many/4 returns a list of {:error, reason} tuples when there was an error loading the data",
         %{loader: loader} do
      log =
        capture_log(fn ->
          result =
            loader
            |> Dataloader.load_many(:test, :users, ["ben", "explode"])
            |> Dataloader.run()
            |> Dataloader.get_many(:test, :users, ["ben", "explode"])

          assert [
                   {:error, {%RuntimeError{message: "hell"}, _stacktrace1}},
                   {:error, {%RuntimeError{message: "hell"}, _stacktrace2}}
                 ] = result
        end)

      assert log =~ "hell"
    end
  end
end
