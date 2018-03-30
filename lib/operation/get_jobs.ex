defmodule Hippy.Operation.GetJobs do
  defstruct charset: "utf-8",
            natural_language: "en",
            printer_uri: nil,
            which_jobs: :completed,
            requested_attributes: [
              "job-id",
              "job-state",
              "job-state-reasons",
              "job-name",
              "job-originating-user-name",
              "job-media-sheets-completed"
            ]
end

defimpl Hippy.OperationRequest, for: Hippy.Operation.GetJobs do
  alias Hippy.{Operation, Request}

  def build_request(op) do
    ipp_printer_uri = String.replace(op.printer_uri, "http://", "ipp://")

    %Request{
      # Should request_id be a parameter to build_request?
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Operation.get_jobs(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.natural_language},
        {:uri, "printer-uri", ipp_printer_uri},
        {:keyword, "which-jobs", to_string(op.which_jobs)},
        {{:set1, :keyword}, "requested-attributes", op.requested_attributes}
      ],
      data: <<>>
    }
  end
end
