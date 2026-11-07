defmodule Hippy.Error do
  @moduledoc """
  An IPP error: a response with a client-error (`0x04xx`) or server-error (`0x05xx`) status.

    * `:status` - the status, e.g. `:client_error_not_found`, or the integer if Hippy doesn't
      know it.
    * `:message` - the response's `status-message`, if the server sent one.
    * `:response` - the whole `Hippy.Response`, e.g. for `Hippy.Response.unsupported/1`.
  """

  defexception [:status, :message, :response]

  @impl true
  def message(%__MODULE__{status: status, message: nil}), do: "IPP error #{format(status)}"

  def message(%__MODULE__{status: status, message: message}),
    do: "IPP error #{format(status)}: #{message}"

  defp format(status) when is_atom(status), do: Atom.to_string(status)
  defp format(status), do: "0x" <> String.pad_leading(Integer.to_string(status, 16), 4, "0")

  @doc false
  # Returns {:ok, response}, or {:error, %Hippy.Error{}} for an error status.
  def from_response(%Hippy.Response{status_code: status} = response) do
    if status_class(status) in [0x04, 0x05] do
      {:error, %__MODULE__{status: status, message: status_message(response), response: response}}
    else
      {:ok, response}
    end
  end

  defp status_class(status) when is_integer(status), do: Bitwise.bsr(status, 8)

  defp status_class(status) do
    case Hippy.IPP.StatusCode.encode(status) do
      {:ok, value} -> status_class(value)
      {:error, _} -> nil
    end
  end

  defp status_message(%Hippy.Response{operation_attributes: attributes}) do
    case List.keyfind(attributes, "status-message", 1) do
      {_syntax, _name, message} when is_binary(message) -> message
      {_syntax, _name, {_language, message}} -> message
      _ -> nil
    end
  end
end
