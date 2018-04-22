defmodule Hippy.Operation.CancelJob do
  @moduledoc """
  Represents a request to cancel a print job from the time it's created up to the time
  it's completed, canceled, or aborted.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri, :job_id]

  defstruct printer_uri: nil,
            job_id: nil,
            charset: @def_charset,
            language: @def_lang

  def new(printer_uri, job_id, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      job_id: job_id,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CancelJob do
  def build_request(op) do
    target = String.replace(op.printer_uri, ~r/^http(s)?/, "ipp")

    %Hippy.Request{
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cancel_job(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {:uri, "printer-uri", target},
        {:integer, "job-id", op.job_id}
      ],
      data: <<>>
    }
  end
end
