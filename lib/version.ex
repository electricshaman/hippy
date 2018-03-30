defmodule Hippy.IPPVersion do
  @enforce_keys [:major, :minor]
  defstruct @enforce_keys

  def new(major, minor) do
    %__MODULE__{major: major, minor: minor}
  end
end
