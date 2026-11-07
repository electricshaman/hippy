defmodule Hippy.Operation.CancelSubscription do
  @moduledoc """
  Cancels a subscription, so the printer stops collecting its events.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri, :subscription_id]

  defstruct printer_uri: nil,
            subscription_id: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{}

  def new(printer_uri, subscription_id, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      subscription_id: subscription_id,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CancelSubscription do
  def build_request(op) do
    Hippy.IPP.Operation.cancel_subscription()
    |> Hippy.Message.build_request(op, [
      {:integer, "notify-subscription-id", op.subscription_id}
    ])
  end
end
