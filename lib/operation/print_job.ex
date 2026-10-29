defmodule Hippy.Operation.PrintJob do
  @moduledoc """
  Represents a request to print a document using a printer on the IPP server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_job_name "Untitled Job"
  @def_orientation Hippy.Protocol.Orientation.portrait()

  @enforce_keys [:printer_uri, :document]

  defstruct printer_uri: nil,
            document: nil,
            charset: @def_charset,
            language: @def_lang,
            job_name: @def_job_name,
            orientation: @def_orientation

  def new(printer_uri, document, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      document: document,
      job_name: Keyword.get(opts, :job_name, @def_job_name),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      orientation: Keyword.get(opts, :orientation, @def_orientation)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.PrintJob do
  def build_request(op) do
    Hippy.Request.new(
      Hippy.Protocol.Operation.print_job(),
      op,
      [{:name_without_language, "job-name", op.job_name}],
      job_attributes: [{:enum, "orientation-requested", op.orientation}],
      data: op.document
    )
  end
end
