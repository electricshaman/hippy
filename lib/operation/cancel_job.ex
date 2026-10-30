defmodule Hippy.Operation.CancelJob do
  @moduledoc """
  Represents a request to cancel a print job from the time it's created up to the time
  it's completed, canceled, or aborted.

  Extra attributes can be sent with the `:operation_attributes` option, as `{syntax, name, value}`
  tuples (see `Hippy.Encoder.encode/1`). Each replaces an attribute of the same name that Hippy
  would otherwise send.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri, :job_id]

  defstruct printer_uri: nil,
            job_id: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: []

  def new(printer_uri, job_id, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      job_id: job_id,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, [])
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CancelJob do
  def build_request(op) do
    Hippy.Request.new(Hippy.IPP.Operation.cancel_job(), op, [
      {:integer, "job-id", op.job_id}
    ])
  end
end
