defmodule Hippy.AttributeGroup do
  @moduledoc "Contains functions for working with attribute groups."

  def to_map([]) do
    Map.new()
  end

  def to_map([head | _] = group) when is_tuple(head) do
    attribute_group_to_map(group)
  end

  def to_map([head | _]) when is_list(head) do
    attribute_group_to_map(head)
  end

  def to_map(_group) do
    {:error, :bad_attribute_group}
  end

  def to_map([head | _] = groups, index) when is_list(head) and is_list(groups) do
    Enum.at(groups, index)
    |> attribute_group_to_map()
  end

  def to_map(_group, _index) do
    {:error, :bad_attribute_group}
  end

  defp attribute_group_to_map(group) do
    for att <- group, into: %{} do
      {_syntax, name, value} = att
      {name, value}
    end
  end
end
