defmodule DataLoaderTest do
  use ExUnit.Case
  doctest DataLoader

  test "greets the world" do
    assert DataLoader.hello() == :world
  end
end
