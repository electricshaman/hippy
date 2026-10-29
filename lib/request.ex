defmodule Hippy.Request do
  @moduledoc """
  An IPP request, built from an operation by `Hippy.Operation.build_request/1`.

  `request_id` is assigned by `Hippy.Server` when the request is sent, unless it's already set.
  """

  defstruct version: Hippy.IPPVersion.new(1, 1),
            operation_id: nil,
            request_id: nil,
            operation_attributes: [],
            job_attributes: [],
            data: <<>>

  @doc """
  Builds a request for an operation on a printer.

  Adds the operation attributes every request starts with (`attributes-charset`,
  `attributes-natural-language` and `printer-uri`) from the operation's `charset`, `language`
  and `printer_uri` fields, followed by `attributes`. Other request fields, such as
  `job_attributes` and `data`, can be given in `fields`.
  """
  def new(operation_id, op, attributes \\ [], fields \\ []) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    operation_attributes = [
      {:charset, "attributes-charset", op.charset},
      {:natural_language, "attributes-natural-language", op.language},
      {:uri, "printer-uri", target} | attributes
    ]

    struct!(
      %__MODULE__{operation_id: operation_id, operation_attributes: operation_attributes},
      fields
    )
  end
end
