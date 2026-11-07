defprotocol Hippy.Operation do
  @moduledoc """
  Builds the request for an operation struct, such as `Hippy.Operation.PrintJob`.

  Implement it for your own struct to add an operation, usually with
  `Hippy.Message.build_request/4`. `Hippy.send_operation/2` sends the result.
  """

  @doc "Returns the request for the operation, as a `Hippy.Message`."
  def build_request(operation)
end
