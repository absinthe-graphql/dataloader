defmodule DataloaderTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  doctest Dataloader

  @data [
    users: [
      [id: "ben", username: "Ben Wilson"],
      [id: "bruce", username: "Bruce Williams"]
    ],
    results: %{
      success_data: {:ok, :value},
      error_data: {:error, :value}
    }
  ]

  defp query(batch_key, ids = %MapSet{}) do
    for id <- ids, into: %{} do
      query(batch_key, id)
    end
  end

  defp query(_batch_key, "explode"), do: raise("hell")

  defp query(:users, id) do
    item =
      @data[:users]
      |> Enum.find(fn data -> data[:id] == id end)

    {id, item}
  end

  defp query(:results, key) do
    item = @data[:results] |> Map.get(key)

    {key, item}
  end

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
        Dataloader.new()
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

  describe "erroring sources" do
    test "get/4 returns error" do
      loader =
        Dataloader.new(get_policy: :tuples, async: true)
        |> Dataloader.add_source(:test, %Dataloader.Source.Error{})

      result =
        loader
        |> Dataloader.load(:test, :sleep, 5)
        |> Dataloader.run()
        |> Dataloader.get(:test, :sleep, 5)

      assert result == {:error, :killed}
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

    test "get/4 returns an {:ok, value} tuple when data is value tuple", %{loader: loader} do
      result =
        loader
        |> Dataloader.load(:test, :results, :success_data)
        |> Dataloader.run()
        |> Dataloader.get(:test, :results, :success_data)

      assert result == {:ok, :value}
    end

    test "get/4 returns an {:error, value} tuple when data is error tuple", %{loader: loader} do
      result =
        loader
        |> Dataloader.load(:test, :results, :error_data)
        |> Dataloader.run()
        |> Dataloader.get(:test, :results, :error_data)

      assert result == {:error, :value}
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
