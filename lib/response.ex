defmodule Hippy.Response do
  defstruct version: nil,
            status_code: nil,
            request_id: nil,
            operation_attributes: [],
            job_attributes: [],
            printer_attributes: [],
            unknown_attributes: [],
            data: nil

  @behaviour Access

  # Access behaviour

  defdelegate fetch(term, key), to: Map
  defdelegate get(structure, key, default), to: Map
  defdelegate get_and_update(data, key, function), to: Map
  defdelegate pop(data, key), to: Map
end
