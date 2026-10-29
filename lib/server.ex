defmodule Hippy.Server do
  @supported_schemes ["ipp", "ipps", "http", "https"]

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
    req = %{req | request_id: req.request_id || System.unique_integer([:positive, :monotonic])}

    case post(endpoint, Hippy.Encoder.encode(req)) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Hippy.Decoder.decode(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, _} = error ->
        error
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

  # ipp and ipps are sent over http and https, on IPP's default port 631 unless one is given.
  defp adjust_scheme(%URI{scheme: "ipp"} = uri) do
    %{uri | scheme: "http", port: uri.port || 631}
  end

  defp adjust_scheme(%URI{scheme: "ipps"} = uri) do
    %{uri | scheme: "https", port: uri.port || 631}
  end

  defp adjust_scheme(%URI{scheme: scheme} = uri) when scheme in ["http", "https"] do
    # Leave as is.
    uri
  end

  defp adjust_scheme(%URI{scheme: scheme}) do
    {:error, {:unsupported_uri_scheme, scheme}}
  end

  defp post(url, body) do
    # Extra Req options (timeouts, TLS settings, etc.) can be supplied via
    # `config :hippy, req_options: [...]`. POSTs are not retried by Req by
    # default, which we rely on so a Print-Job is never submitted twice.
    options =
      Keyword.merge(
        [body: body, headers: [{"content-type", "application/ipp"}], decode_body: false],
        Application.get_env(:hippy, :req_options, [])
      )

    Req.post(url, options)
  end
end
