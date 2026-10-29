defmodule Hippy.IPPRegistryTest do
  @moduledoc """
  Checks the Hippy.IPP modules against the IANA IPP registry.

  `test/fixtures/ipp_registry.json` is extracted from the registry by
  `mix run scripts/update_ipp_registry.exs`. Rerun it to pick up new registrations.
  """

  use ExUnit.Case, async: true

  @registry "test/fixtures/ipp_registry.json" |> File.read!() |> Jason.decode!()

  # Names Hippy defined before the registry changed them. Kept for compatibility.
  @renamed %{
    {"operations-supported", 0x16} => :create_printer_subscription,
    {"operations-supported", 0x17} => :create_job_subscription
  }

  defp to_atom(name) do
    name
    |> String.replace(~r/\s*\((deprecated|obsolete)\)$/, "")
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp values(section),
    do: Enum.map(section, fn {value, name} -> {String.to_integer(value), name} end)

  test "every registered enum value is decoded, with the registry's name" do
    for {attribute, values} <- @registry["enums"], {value, %{"name" => name}} <- values do
      value = String.to_integer(value)
      expected = Map.get(@renamed, {attribute, value}, to_atom(name))

      assert Hippy.IPP.Enum.decode(attribute, value) == {:ok, expected},
             "#{attribute} #{value} should decode to #{inspect(expected)}"
    end
  end

  test "attributes that reuse another attribute's enum decode the same values" do
    # Status codes are a section of their own rather than an enum attribute.
    enums = Map.put(@registry["enums"], "status-code", @registry["status_codes"])

    for {attribute, base} <- @registry["enum_aliases"], {value, _} <- Map.fetch!(enums, base) do
      value = String.to_integer(value)

      assert Hippy.IPP.Enum.decode(attribute, value) == Hippy.IPP.Enum.decode(base, value),
             "#{attribute} should use the #{base} enum"
    end
  end

  test "every registered status code is defined" do
    for {value, name} <- values(@registry["status_codes"]) do
      assert Hippy.IPP.StatusCode.decode(value) == {:ok, to_atom(name)}
    end
  end

  test "every registered attribute group tag is defined" do
    for {value, name} <- values(@registry["delimiter_tags"]) do
      expected = name |> String.replace_suffix("-tag", "") |> to_atom()
      assert Hippy.IPP.DelimiterTag.decode(value) == {:ok, expected}
    end
  end

  test "every registered value tag is defined" do
    # Hippy's names are snake_case versions of the registry's camelCase ones, so only check the
    # values. 0x7F is the extension tag, which isn't a syntax of its own.
    for {value, name} <- values(@registry["value_tags"]), value != 0x7F do
      assert {:ok, _} = Hippy.IPP.ValueTag.decode(value), "value tag #{value} (#{name})"
    end
  end
end
