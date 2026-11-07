defmodule Hippy.Response do
  @moduledoc false

  # Responses are Hippy.Message structs since 0.7. These helpers are kept for one release.

  @deprecated "Use Hippy.Message.job/1 instead"
  defdelegate job(message), to: Hippy.Message

  @deprecated "Use Hippy.Message.jobs/1 instead"
  defdelegate jobs(message), to: Hippy.Message

  @deprecated "Use Hippy.Message.printer/1 instead"
  defdelegate printer(message), to: Hippy.Message

  @deprecated "Use Hippy.Message.printers/1 instead"
  defdelegate printers(message), to: Hippy.Message

  @deprecated "Use Hippy.Message.operation_attributes/1 instead"
  def operation(message), do: Hippy.Message.operation_attributes(message)

  @deprecated "Use Hippy.Message.unsupported/1 instead"
  defdelegate unsupported(message), to: Hippy.Message
end
