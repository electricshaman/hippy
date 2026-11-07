defmodule Hippy.HTTPError do
  @moduledoc """
  A request answered with an HTTP error instead of an IPP response, for example 401 when a
  printer needs authentication, or 426 when it needs HTTPS.

    * `:status` - the HTTP status code.
    * `:body` - the response body.
  """

  defexception [:status, :body]

  @reasons %{
    400 => "Bad Request",
    401 => "Unauthorized",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    413 => "Payload Too Large",
    426 => "Upgrade Required",
    500 => "Internal Server Error",
    503 => "Service Unavailable"
  }

  @impl true
  def message(%__MODULE__{status: status}) do
    case @reasons do
      %{^status => reason} -> "HTTP #{status} #{reason}"
      _ -> "HTTP #{status}"
    end
  end
end
