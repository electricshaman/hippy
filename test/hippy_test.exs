defmodule HippyTest do
  use ExUnit.Case
  doctest Hippy

  test "greets the world" do
    assert Hippy.hello() == :world
  end
end
