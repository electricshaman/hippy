defmodule Hippy.IPP.DocumentState do
  @moduledoc "Values of the `document-state` attribute, from the IANA IPP registry."

  use Hippy.IPP.Enum, %{
    pending: 3,
    processing: 5,
    processing_stopped: 6,
    canceled: 7,
    aborted: 8,
    completed: 9
  }
end
