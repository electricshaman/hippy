defmodule Hippy.Server do
  @supported_schemes ["ipp", "http", "https"]

  def send_operation(op) do
    if is_nil(op.printer_uri) do
      {:error, :printer_uri_required}
    else
      with {:ok, endpoint} <- format_endpoint(op.printer_uri) do
        send_operation(op, endpoint)
      end
    end
  end

  def send_operation(_op, nil) do
    {:error, :printer_uri_required}
  end

  def send_operation(op, endpoint) do
    Hippy.Operation.build_request(op)
    |> send_request(endpoint)
  end

  def send_request(%Hippy.Request{} = req, endpoint) do
    # TODO: Rework error handling.  It's broken.
    with {:ok, %{body: body, status_code: 200}} <- post(endpoint, Hippy.Encoder.encode(req)) do
      {:ok, Hippy.Decoder.decode(body)}
    end
  end

  def format_endpoint(printer_uri) when is_nil(printer_uri) do
    {:error, :printer_uri_required}
  end

  def format_endpoint(printer_uri) do
    with %URI{scheme: scheme} = uri when scheme in @supported_schemes <- URI.parse(printer_uri),
         %URI{} = uri <- adjust_scheme(uri) do
      {:ok, to_string(uri)}
    else
      %URI{scheme: scheme} ->
        {:error, {:unsupported_uri_scheme, scheme}}

      error ->
        error
    end
  end

  defp adjust_scheme(%URI{scheme: "ipp"} = uri) do
    # Translate scheme back to http if we've found an ipp scheme in the URI.
    %{uri | scheme: "http"}
  end

  defp adjust_scheme(%URI{scheme: scheme} = uri) when scheme in ["http", "https"] do
    # Leave as is.
    uri
  end

  defp adjust_scheme(%URI{scheme: scheme}) do
    {:error, {:unsupported_uri_scheme, scheme}}
  end

  defp post(url, body) do
    #    headers = ["Content-Type": "application/ipp", "Authorization": "Basic #####"]
    headers = ["Content-Type": "application/ipp"]
    HTTPoison.post(url, body, headers, ssl: [verify: :verify_none])
  end
end
