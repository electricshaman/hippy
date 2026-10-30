defmodule Hippy.Server do
  @supported_schemes ["ipp", "ipps", "http", "https"]

  @doc """
  Sends an operation to a printer and decodes the response.

  The request is sent to the operation's `printer_uri`, or `server_uri` for operations addressed
  to the server such as `Hippy.Operation.CupsGetPrinters` (`ipp` and `ipps` are sent over `http`
  and `https`).

  ## Options

    * `:req_options` - options for `Req` (authentication, TLS, timeouts, etc.) for this request,
      merged over `config :hippy, req_options: [...]`. For example
      `req_options: [auth: {:basic, "user:pass"}]`.
    * `:endpoint` - the URL to send the request to, instead of the one derived from
      `printer_uri`.

  For compatibility, the second argument can also be the endpoint URL.
  """
  def send_operation(op, opts \\ [])

  def send_operation(op, endpoint) when is_binary(endpoint) or is_nil(endpoint) do
    send_operation(op, endpoint: endpoint)
  end

  def send_operation(op, opts) when is_list(opts) do
    with {:ok, endpoint} <- endpoint(op, opts) do
      Hippy.Operation.build_request(op)
      |> send_request(endpoint, opts)
    end
  end

  @doc """
  Sends a request to an endpoint URL and decodes the response.

  Takes the same `:req_options` option as `send_operation/2`.
  """
  def send_request(%Hippy.Request{} = req, endpoint, opts \\ []) do
    req = %{req | request_id: req.request_id || System.unique_integer([:positive, :monotonic])}

    case post(endpoint, Hippy.Encoder.encode(req), Keyword.get(opts, :req_options, [])) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Hippy.Decoder.decode(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, _} = error ->
        error
    end
  end

  defp endpoint(op, opts) do
    case Keyword.fetch(opts, :endpoint) do
      {:ok, nil} -> {:error, :printer_uri_required}
      {:ok, endpoint} -> {:ok, endpoint}
      :error -> format_endpoint(target_uri(op))
    end
  end

  # Most operations are sent to a printer. Some, such as CUPS-Get-Printers, are sent to the
  # server itself.
  defp target_uri(op), do: Map.get(op, :printer_uri) || Map.get(op, :server_uri)

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

  defp post(url, body, req_options) do
    # Req.merge/2 combines headers rather than replacing them, so configured headers don't drop
    # the IPP content type. POSTs are not retried by Req by default, which we rely on so a
    # Print-Job is never submitted twice.
    Req.new(body: body, headers: [{"content-type", "application/ipp"}], decode_body: false)
    |> Req.merge(Application.get_env(:hippy, :req_options, []))
    |> Req.merge(req_options)
    |> Req.post(url: url)
  end
end
