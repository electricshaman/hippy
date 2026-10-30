defmodule Hippy.AttributeGroup do
  @moduledoc """
  Contains functions for working with attribute groups.

  `to_map/1` returns a group as a map of attribute names to values. Attributes the IANA registry
  defines as sets (such as `job-state-reasons`, or `finishings-col`'s `folding` member) are always
  lists, even with a single value.
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
    Map.put(acc, name, wrap_set(syntax, [name], map_value(value, [name])))
  end

  # `path` is the attribute name followed by any collection member names, as used by
  # `Hippy.IPP.Attributes`, or nil when converting without knowing where the value came from.
  defp map_value(%_{} = struct, _path), do: struct
  defp map_value(map, path) when is_map(map), do: compact_members(map, path)
  defp map_value(values, path) when is_list(values), do: Enum.map(values, &map_value(&1, path))
  defp map_value(value, _path), do: value

  defp compact_members(members, path) do
    Map.new(members, fn {member, value} ->
      path = if path, do: path ++ [member]
      {member, member_value(value, path)}
    end)
  end

  # Member values are attribute tuples, or a list of them for a member with several values.
  defp member_value(values, path) when is_list(values),
    do: Enum.map(values, &member_entry(&1, path))

  defp member_value({syntax, _name, _value} = entry, path),
    do: wrap_set(syntax, path, member_entry(entry, path))

  defp member_entry({:collection, _name, members}, path), do: compact_members(members, path)
  defp member_entry({_syntax, _name, value}, _path), do: value

  @out_of_band [
    :unsupported,
    :unknown,
    :no_value,
    :not_settable,
    :delete_attribute,
    :admin_define
  ]

  # Attributes and collection members the IANA registry defines as sets (1setOf) are always lists,
  # even with one value, so callers don't have to handle both. Attributes it doesn't know are left
  # as they are, and so are out-of-band values such as :no_value.
  defp wrap_set(_syntax, nil, value), do: value
  defp wrap_set(syntax, _path, value) when syntax in @out_of_band, do: value
  defp wrap_set(_syntax, _path, value) when is_list(value), do: value

  defp wrap_set(_syntax, path, value) do
    if Hippy.IPP.Attributes.set?(path), do: [value], else: value
  end

  @doc false
  # Converts a collection's members without knowing where it came from, so sets aren't wrapped.
  def compact(%_{} = struct), do: struct
  def compact(map) when is_map(map), do: compact_members(map, nil)
  def compact({:collection, nil, members}), do: compact(members)
  def compact({_, nil, value}), do: value
end
