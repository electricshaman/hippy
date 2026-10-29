defmodule Hippy.IPP.TransmissionStatus do
  @moduledoc "Values of the `transmission-status` attribute, from the IANA IPP registry."

  use Hippy.IPP.Enum, %{
    pending: 3,
    pending_retry: 4,
    processing: 5,
    canceled: 7,
    aborted: 8,
    completed: 9
  }
end
