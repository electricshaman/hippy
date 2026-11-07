defmodule Hippy.IPPVersion do
  @moduledoc false

  # Unused since 0.7: messages carry the version as {major, minor}.

  @enforce_keys [:major, :minor]
  defstruct @enforce_keys

  @deprecated "Messages carry the version as {major, minor}"
  def new(major, minor) do
    %__MODULE__{major: major, minor: minor}
  end
end
