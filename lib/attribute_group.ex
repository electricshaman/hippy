defmodule Hippy.AttributeGroup do
  @moduledoc "Contains functions for working with attribute groups."

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
    Enum.at(groups, index)
    |> group_to_map()
  end

  def to_map(_group, _index) do
    {:error, :bad_attribute_group}
  end

  defp group_to_map(group) do
    Enum.reduce(group, %{}, &att_to_map/2)
  end

  # Struct
  defp att_to_map({_syntax, name, %_{} = value}, acc) do
    Map.put(acc, name, value)
  end

  defp att_to_map({_syntax, name, value}, acc) when is_map(value) do
    Map.put(acc, name, compact(value))
  end

  defp att_to_map({_syntax, name, value}, acc) when is_list(value) and is_map(hd(value)) do
    Map.put(acc, name, Enum.map(value, fn i -> compact(i) end))
  end

  defp att_to_map({_syntax, name, value}, acc) do
    Map.put(acc, name, value)
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
