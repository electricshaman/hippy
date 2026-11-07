defmodule Hippy.Request do
  @moduledoc false

  # Requests are Hippy.Message structs since 0.7. new/4 is kept for one release, for custom
  # Hippy.Operation implementations.

  @deprecated "Use Hippy.Message.build_request/4 instead"
  def new(operation_id, op, attributes \\ [], fields \\ []),
    do: Hippy.Message.build_request(operation_id, op, attributes, fields)
end
