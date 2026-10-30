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
    * `:raw` - when `true`, return the response exactly as it was sent (see
      `Hippy.Decoder.decode/2`).

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

  # CUPS operations addressed to the server as a whole, which take no printer-uri.
  @server_operations [
    :cups_get_default,
    :cups_get_printers,
    :cups_get_classes,
    :cups_get_devices,
    :cups_get_ppds
  ]

  @doc """
  Sends any operation, by name or id, with attributes given as a map. See `Hippy.request/4`.
  """
  def request(uri, operation, attributes \\ %{}, opts \\ []) do
    with {:ok, operation_id, name} <- operation_id(operation),
         {:ok, endpoint} <- endpoint(%{printer_uri: uri}, opts) do
      op =
        %{
          charset: Keyword.get(opts, :charset, "utf-8"),
          language: Keyword.get(opts, :language, "en"),
          attributes: attributes,
          operation_attributes: Keyword.get(opts, :operation_attributes, []),
          job_attributes: Keyword.get(opts, :job_attributes, []),
          groups: Keyword.get(opts, :groups, [])
        }
        |> put_target(uri, Keyword.get_lazy(opts, :target, fn -> target(uri, name) end))

      operation_id
      |> Hippy.Request.new(op, [], data: Keyword.get(opts, :document, <<>>))
      |> send_request(endpoint, opts)
    end
  end

  defp operation_id(id) when is_integer(id) do
    case Hippy.IPP.Operation.decode(id) do
      {:ok, name} -> {:ok, id, name}
      {:error, _} -> {:ok, id, nil}
    end
  end

  defp operation_id(name) when is_atom(name) do
    case Hippy.IPP.Operation.encode(name) do
      {:ok, id} -> {:ok, id, name}
      {:error, _} -> {:error, {:unknown_operation, name}}
    end
  end

  defp target(uri, name) do
    cond do
      name in @server_operations -> :server
      URI.parse(uri).path =~ ~r{/jobs/\d+/?$} -> :job
      true -> :printer
    end
  end

  # The printer-uri (or job-uri) attribute that says what the operation is about.
  defp put_target(op, uri, :printer), do: Map.put(op, :printer_uri, uri)

  defp put_target(op, uri, :job) do
    job_uri = {:uri, "job-uri", String.replace(uri, ~r/^http/, "ipp")}
    Map.update!(op, :operation_attributes, &[job_uri | &1])
  end

  defp put_target(op, _uri, :server), do: op

  @doc """
  Sends a request to an endpoint URL and decodes the response.

  Takes the same `:req_options` and `:raw` options as `send_operation/2`.
  """
  def send_request(%Hippy.Request{} = req, endpoint, opts \\ []) do
    req = %{req | request_id: req.request_id || System.unique_integer([:positive, :monotonic])}

    case post(endpoint, Hippy.Encoder.encode(req), Keyword.get(opts, :req_options, [])) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Hippy.Decoder.decode(body, Keyword.take(opts, [:raw]))}

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
