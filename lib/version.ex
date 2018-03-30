defmodule Hippy.IPPVersion do
  @enforce_keys [:major, :minor]
  defstruct @enforce_keys

  alias __MODULE__

  def new(major, minor) do
    %IPPVersion{major: major, minor: minor}
  end
end
