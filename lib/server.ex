defmodule Hippy.Server do
  alias Hippy.{Request, Encoder, Decoder}

  def send(%Request{} = req, endpoint) do
    # TODO: Rework error handling.
    with {:ok, %{body: body, status_code: 200}} <- post(endpoint, Encoder.encode(req)) do
      {:ok, Decoder.decode(body)}
    end
  end

  def send(operation, endpoint) do
    Hippy.OperationRequest.build_request(operation)
    |> Hippy.Server.send(endpoint)
  end

  defp post(url, body) do
    headers = ["Content-Type": "application/ipp"]
    HTTPoison.post(url, body, headers)
  end
end
