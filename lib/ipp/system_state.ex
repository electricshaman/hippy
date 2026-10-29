defmodule Hippy.IPP.SystemState do
  @moduledoc "Values of the `system-state` attribute, from the IANA IPP registry."

  use Hippy.IPP.Enum, %{
    idle: 3,
    processing: 4,
    stopped: 5
  }
end
