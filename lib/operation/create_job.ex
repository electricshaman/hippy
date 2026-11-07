defmodule Hippy.Operation.CreateJob do
  @moduledoc """
  Creates a job without a document. Add its documents with `Hippy.Operation.SendDocument`,
  marking the last one with `last_document: true` (the default). The job prints once the last
  document arrives.

  Use it for a job made of several documents, which print as one job (stapled together, for
  example), or to create the job before the document is ready:

      {:ok, res} = uri |> CreateJob.new(job_name: "Contract") |> Hippy.send_operation()
      job_id = res |> Hippy.Message.job() |> Map.fetch!("job-id")

      {:ok, _} =
        uri
        |> SendDocument.new(job_id, cover_letter,
          document_format: "application/pdf",
          last_document: false
        )
        |> Hippy.send_operation()

      {:ok, _} =
        uri
        |> SendDocument.new(job_id, contract, document_format: "application/pdf")
        |> Hippy.send_operation()

  CUPS only lets the job's owner send its documents, so send both operations authenticated, as
  the same user (see "Authentication" in the README).

  ## Options

  The same as `Hippy.Operation.PrintJob`, apart from `:document_format`, which is given for each
  document with `Hippy.Operation.SendDocument`.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_job_name "Untitled Job"
  @def_orientation Hippy.IPP.Orientation.portrait()

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{},
            job_attributes: [],
            job_name: @def_job_name,
            orientation: @def_orientation

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      job_name: Keyword.get(opts, :job_name, @def_job_name),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{}),
      job_attributes: Keyword.get(opts, :job_attributes, []),
      orientation: Keyword.get(opts, :orientation, @def_orientation)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CreateJob do
  def build_request(op) do
    Hippy.IPP.Operation.create_job()
    |> Hippy.Message.build_request(
      op,
      [{:name_without_language, "job-name", op.job_name}],
      job_attributes: [{:enum, "orientation-requested", op.orientation}]
    )
  end
end
