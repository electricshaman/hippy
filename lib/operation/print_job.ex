defmodule Hippy.Operation.PrintJob do
  @moduledoc """
  Represents a request to print a document using a printer on the IPP server.

  ## Options

    * `:job_name` - defaults to `"Untitled Job"`.
    * `:document_format` - the MIME media type of the document, e.g. `"application/pdf"`. When
      not given, the printer decides (CUPS detects the type automatically).
    * `:orientation` - an `Hippy.IPP.Orientation` value, defaults to portrait.
    * `:charset` and `:language` - default to `"utf-8"` and `"en"`.
    * `:operation_attributes` and `:job_attributes` - extra attributes for each group, as
      `{syntax, name, value}` tuples (see `Hippy.Encoder.encode/1`). Each replaces an attribute
      of the same name that Hippy would otherwise send.
    * `:groups` - other attribute groups, as `{tag, attributes}` (see `Hippy.Request`), e.g. a
      `:subscription_attributes` group to be notified about the job.

  For example, to print two double-sided copies:

      PrintJob.new(uri, doc,
        document_format: "application/pdf",
        job_attributes: [
          {:integer, "copies", 2},
          {:keyword, "sides", "two-sided-long-edge"}
        ]
      )
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_job_name "Untitled Job"
  @def_orientation Hippy.IPP.Orientation.portrait()

  @enforce_keys [:printer_uri, :document]

  defstruct printer_uri: nil,
            document: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            job_attributes: [],
            job_name: @def_job_name,
            document_format: nil,
            orientation: @def_orientation

  def new(printer_uri, document, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      document: document,
      job_name: Keyword.get(opts, :job_name, @def_job_name),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      job_attributes: Keyword.get(opts, :job_attributes, []),
      document_format: Keyword.get(opts, :document_format),
      orientation: Keyword.get(opts, :orientation, @def_orientation)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.PrintJob do
  def build_request(op) do
    Hippy.Request.new(
      Hippy.IPP.Operation.print_job(),
      op,
      [{:name_without_language, "job-name", op.job_name}] ++ document_format(op),
      job_attributes: [{:enum, "orientation-requested", op.orientation}],
      data: op.document
    )
  end

  defp document_format(%{document_format: nil}), do: []
  defp document_format(op), do: [{:mime_media_type, "document-format", op.document_format}]
end
