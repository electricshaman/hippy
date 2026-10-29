defmodule Hippy.DeprecatedTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @renamed [
    DelimiterTag,
    Enum,
    Finishing,
    JobState,
    Operation,
    Orientation,
    PrintQuality,
    PrinterState,
    PrinterType,
    PrinterWifiState,
    ResolutionUnit,
    StatusCode,
    ValueTag
  ]

  test "old Hippy.Protocol modules delegate every function and are deprecated" do
    for name <- @renamed do
      old = Module.concat(Hippy.Protocol, name)
      new = Module.concat(Hippy.IPP, name)

      assert old.__info__(:functions) |> Enum.sort() == new.__info__(:functions) |> Enum.sort()

      for {fun, arity} <- new.__info__(:functions) do
        assert {{fun, arity}, "Use #{inspect(new)}.#{fun}/#{arity} instead"} in old.__info__(
                 :deprecated
               )
      end
    end
  end

  test "old modules return the same values" do
    assert apply(Hippy.Protocol.Orientation, :landscape, []) == Hippy.IPP.Orientation.landscape()
    assert apply(Hippy.Protocol.JobState, :decode, [9]) == {:ok, :completed}
    assert apply(Hippy.Protocol.Enum, :decode, ["job-state", 9]) == {:ok, :completed}
  end

  test "use Hippy.Protocol.Enum still defines an enum, with a warning" do
    stderr =
      capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule Hippy.DeprecatedTest.OldEnum do
          use Hippy.Protocol.Enum, %{on: 1, off: 2}
        end
        """)
      end)

    assert stderr =~ "use Hippy.Protocol.Enum is deprecated, use Hippy.IPP.Enum instead"
    assert apply(Hippy.DeprecatedTest.OldEnum, :off, []) == 2
    assert apply(Hippy.DeprecatedTest.OldEnum, :decode, [1]) == {:ok, :on}
  end

  test "@behaviour Hippy.Protocol.Enum still compiles without warnings" do
    stderr =
      capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule Hippy.DeprecatedTest.OldBehaviour do
          @behaviour Hippy.Protocol.Enum

          @impl true
          def decode(value), do: {:ok, value}
        end
        """)
      end)

    assert stderr == ""
  end
end
