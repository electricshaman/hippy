defmodule Hippy.Error do
  @moduledoc """
  An IPP error: a response with a client-error (`0x04xx`) or server-error (`0x05xx`) status.

    * `:status` - the status, e.g. `:client_error_not_found`, or the integer if Hippy doesn't
      know it.
    * `:message` - the response's `status-message`, if the server sent one.
    * `:response` - the whole response, a `Hippy.Message`, e.g. for `Hippy.Message.unsupported/1`.
  """

  defexception [:status, :message, :response]

  @impl true
  def message(%__MODULE__{status: status, message: nil}), do: "IPP error #{format(status)}"

  def message(%__MODULE__{status: status, message: message}),
    do: "IPP error #{format(status)}: #{message}"

  defp format(status) when is_atom(status), do: Atom.to_string(status)
  defp format(status), do: "0x" <> String.pad_leading(Integer.to_string(status, 16), 4, "0")

  @doc false
  # Returns {:ok, message}, or {:error, %Hippy.Error{}} for an error status.
  def from_response(%Hippy.Message{code: code} = message) do
    if Bitwise.bsr(code, 8) in [0x04, 0x05] do
      {:error,
       %__MODULE__{
         status: Hippy.Message.status(message),
         message: status_message(message),
         response: message
       }}
    else
      {:ok, message}
    end
  end

  defp status_message(%Hippy.Message{groups: [{:operation, attributes} | _]}) do
    case List.keyfind(attributes, "status-message", 0) do
      {_name, [{_syntax, {_language, text}} | _]} -> text
      {_name, [{_syntax, text} | _]} when is_binary(text) -> text
      _ -> nil
    end
  end

  defp status_message(_message), do: nil
end
