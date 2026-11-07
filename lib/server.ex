defmodule Hippy.Server do
  @moduledoc false

  # Hippy's public functions delegate here; see Hippy for their docs.

  @supported_schemes ["ipp", "ipps", "http", "https"]

  @doc """
  Sends an operation to a printer and decodes the response.

  Returns `{:ok, %Hippy.Message{}}`, or `{:error, error}` where `error` is an exception:

    * `Hippy.Error` when the printer returns an IPP error (a client-error or server-error
      status, such as `:client_error_not_found`). It keeps the whole response.
    * `Hippy.HTTPError` when it answers with an HTTP error instead, e.g. 401 Unauthorized.
    * Req's exceptions, such as `Req.TransportError`, when it can't be reached or times out.

  So `Exception.message/1` describes any error once the request is sent.

  `{:ok, response}` can still mean the printer ignored or changed some attributes it doesn't
  support (status `:successful_ok_ignored_or_substituted_attributes`).
  `Hippy.Message.unsupported/1` lists them.

  The request is sent to the operation's `printer_uri`, or `server_uri` for operations addressed
  to the server such as `Hippy.Operation.CupsGetPrinters` (`ipp` and `ipps` are sent over `http`
  and `https`).

  ## Options

    * `:timeout` - how long to wait, in milliseconds, both to connect and for the response.
      Req's defaults apply otherwise (15 seconds for the response).
    * `:req_options` - options for `Req` (authentication, TLS, etc.) for this request, merged
      over `config :hippy, req_options: [...]`. For example
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
      |> send_message(endpoint, opts)
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
  Sends any operation, by name or id, with attributes given as a map. See
  `Hippy.send_operation/4`.
  """
  def send_operation(uri, operation, attributes, opts \\ []) when is_binary(uri) do
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
      |> Hippy.Message.build_request(op, [], data: Keyword.get(opts, :document, <<>>))
      |> send_message(endpoint, opts)
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

  @deprecated "Use Hippy.send_message/3 instead"
  def send_request(message, endpoint, opts \\ []), do: send_message(message, endpoint, opts)

  def send_message(%Hippy.Message{} = message, endpoint, opts \\ []) do
    message = %{
      message
      | request_id: message.request_id || System.unique_integer([:positive, :monotonic])
    }

    case post(endpoint, Hippy.Encoder.encode(message), opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        body
        |> Hippy.Message.decode()
        |> Hippy.Error.from_response()

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %Hippy.HTTPError{status: status, body: body}}

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

  defp post(url, body, opts) do
    # Req.merge/2 combines headers rather than replacing them, so configured headers don't drop
    # the IPP content type. POSTs are not retried by Req by default, which we rely on so a
    # Print-Job is never submitted twice.
    Req.new(body: body, headers: [{"content-type", "application/ipp"}], decode_body: false)
    |> Req.merge(Application.get_env(:hippy, :req_options, []))
    |> Req.merge(req_options(opts))
    |> Req.post(url: url)
  end

  # :timeout sets both the connect and receive timeouts, unless req_options sets them.
  defp req_options(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    case Keyword.fetch(opts, :timeout) do
      {:ok, timeout} ->
        req_options
        |> Keyword.put_new(:receive_timeout, timeout)
        |> Keyword.update(
          :connect_options,
          [timeout: timeout],
          &Keyword.put_new(&1, :timeout, timeout)
        )

      :error ->
        req_options
    end
  end
end
