defmodule Hippy.Response do
  @moduledoc """
  A decoded IPP response.

  Attributes are kept as `{syntax, name, value}` tuples in the order the printer sent them.
  `job_attributes` is a list of groups, one per job. The functions in this module return
  attributes as maps of names to values instead:

      {:ok, res} = Hippy.send_operation(PrintJob.new(uri, doc))
      Hippy.Response.job(res)["job-id"]
  """

  alias Hippy.AttributeGroup

  defstruct version: nil,
            status_code: nil,
            request_id: nil,
            operation_attributes: [],
            job_attributes: [],
            printer_attributes: [],
            unsupported_attributes: [],
            unknown_attributes: [],
            data: nil

  @doc """
  Returns the job in the response as a map, or `nil` if there is none.

  For responses about a single job, such as Print-Job and Get-Job-Attributes. When the response
  has several jobs, returns the first one.
  """
  def job(%__MODULE__{job_attributes: [first | _]}), do: AttributeGroup.to_map(first)
  def job(%__MODULE__{}), do: nil

  @doc "Returns each job in the response as a map, such as for Get-Jobs."
  def jobs(%__MODULE__{job_attributes: jobs}), do: Enum.map(jobs, &AttributeGroup.to_map/1)

  @doc "Returns the printer attributes as a map, such as for Get-Printer-Attributes."
  def printer(%__MODULE__{printer_attributes: attributes}), do: AttributeGroup.to_map(attributes)

  @doc "Returns the operation attributes as a map (e.g. `status-message`)."
  def operation(%__MODULE__{operation_attributes: attributes}),
    do: AttributeGroup.to_map(attributes)

  @doc """
  Returns the attributes the printer didn't support as a map, with the values that were sent.
  """
  def unsupported(%__MODULE__{unsupported_attributes: attributes}),
    do: AttributeGroup.to_map(attributes)

  @behaviour Access

  # Access behaviour

  defdelegate fetch(term, key), to: Map
  defdelegate get(structure, key, default), to: Map
  defdelegate get_and_update(data, key, function), to: Map
  defdelegate pop(data, key), to: Map
end
