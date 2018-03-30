defmodule Hippy.JobState do
  use Hippy.Enum, %{
    pending: 0x3,
    pending_held: 0x4,
    processing: 0x5,
    processing_stopped: 0x6,
    canceled: 0x7,
    aborted: 0x8,
    completed: 0x9,
    nil: 0x0
  }
end
