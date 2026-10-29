defmodule Hippy.IPP.ResourceState do
  @moduledoc "Values of the `resource-state` attribute, from the IANA IPP registry."

  use Hippy.IPP.Enum, %{
    pending: 3,
    available: 4,
    installed: 5,
    canceled: 6,
    aborted: 7
  }
end
