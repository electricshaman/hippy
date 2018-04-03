defmodule Hippy.AttributeGroup do
  @moduledoc "Contains functions for working with attribute groups."

  def to_map([{_, _, _} | _tail] = group) do
    for att <- group, into: %{} do
      {_syntax, name, value} = att
      {name, value}
    end
  end

  def to_map(_group) do
    {:error, :bad_attribute_group}
  end
end
