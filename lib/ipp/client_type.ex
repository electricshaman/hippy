defmodule Hippy.IPP.ClientType do
  @moduledoc "Values of the `client-type` attribute, from the IANA IPP registry."

  use Hippy.IPP.Enum, %{
    application: 3,
    operating_system: 4,
    driver: 5,
    other: 6
  }
end
