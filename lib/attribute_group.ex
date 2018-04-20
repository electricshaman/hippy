defmodule Hippy.AttributeGroup do
  @moduledoc "Contains functions for working with attribute groups."

  def to_map([{_, _, _} | _tail] = group) do
    attribute_group_to_map(group)
  end

  def to_map([[{_, _, _}|_] = group | _tail]) do
    attribute_group_to_map(group)
  end

  def to_map(_group) do
    {:error, :bad_attribute_group}
  end

  def to_map([[{_, _, _}|_] | _tail] = groups, index) do
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
