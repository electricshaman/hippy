defmodule Hippy.Operation.PrintJob do
  defstruct charset: "utf-8",
            natural_language: "en",
            printer_uri: nil,
            job_name: "Default Name",
            document_data: nil
end

defimpl Hippy.OperationRequest, for: Hippy.Operation.PrintJob do
  alias Hippy.{Operation, Request}

  def build_request(op) do
    ipp_printer_uri = String.replace(op.printer_uri, "http://", "ipp://")

    %Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Operation.print_job(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.natural_language},
        {:uri, "printer-uri", ipp_printer_uri},
        {:name_without_language, "job-name", op.job_name}
      ],
      data: op.document_data
    }
  end
end
