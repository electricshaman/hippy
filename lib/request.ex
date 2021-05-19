defmodule Hippy.Request do
  defstruct version: Hippy.IPPVersion.new(2, 0),
            operation_id: nil,
            request_id: nil,
            operation_attributes: [],
            job_attributes: [],
            printer_attributes: [],
            data: nil
end
