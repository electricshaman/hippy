defmodule Hippy.AttributeGroup do
  @moduledoc """
  Contains functions for working with attribute groups.

  `to_map/1` returns a group as a map of attribute names to values. Attributes the IANA registry
  defines as sets (such as `job-state-reasons`) are always lists, even with a single value.
  """

  def to_map([]) do
    Map.new()
  end

  def to_map([head | _] = group) when is_tuple(head) do
    group_to_map(group)
  end

  def to_map([head | _]) when is_list(head) do
    group_to_map(head)
  end

  def to_map(_group) do
    {:error, :bad_attribute_group}
  end

  def to_map([head | _] = groups, index) when is_list(head) and is_list(groups) do
    case Enum.at(groups, index) do
      nil -> {:error, :bad_attribute_group}
      group -> group_to_map(group)
    end
  end

  def to_map(_group, _index) do
    {:error, :bad_attribute_group}
  end

  defp group_to_map(group) do
    Enum.reduce(group, %{}, &att_to_map/2)
  end

  defp att_to_map({syntax, name, value}, acc) do
    Map.put(acc, name, wrap_set(syntax, name, map_value(value)))
  end

  defp map_value(%_{} = struct), do: struct
  defp map_value(map) when is_map(map), do: compact(map)
  defp map_value([head | _] = values) when is_map(head), do: Enum.map(values, &compact/1)
  defp map_value(value), do: value

  @out_of_band [
    :unsupported,
    :unknown,
    :no_value,
    :not_settable,
    :delete_attribute,
    :admin_define
  ]

  # Attributes the IANA registry defines as sets (1setOf) are always lists, even with one value,
  # so callers don't have to handle both. Attributes it doesn't know are left as they are, and so
  # are out-of-band values such as :no_value.
  defp wrap_set(syntax, _name, value) when syntax in @out_of_band, do: value
  defp wrap_set(_syntax, _name, value) when is_list(value), do: value

  defp wrap_set(_syntax, name, value) do
    if Hippy.IPP.Attributes.set?(name), do: [value], else: value
  end

  def compact(%_{} = struct) do
    struct
  end

  def compact(map) when is_map(map) do
    Enum.reduce(map, Map.new(), fn {k, v}, acc ->
      case v do
        val when is_list(val) ->
          Map.put(acc, k, Enum.map(val, fn i -> compact(i) end))

        {:collection, _, l} when is_list(l) ->
          Map.put(acc, k, Enum.map(l, fn i -> compact(i) end))

        {:collection, nil, m} ->
          Map.put(acc, k, compact(m))

        {_, nil, val} ->
          Map.put(acc, k, val)
      end
    end)
  end

  def compact({:collection, nil, m}) do
    compact(m)
  end

  def compact({_, nil, v}) do
    v
  end
end
