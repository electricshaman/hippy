defmodule Hippy.Operation.RenewSubscription do
  @moduledoc """
  Renews a subscription before its lease runs out (see `notify-lease-expiration-time` in
  `Hippy.Message.subscriptions/1`).

  ## Options

    * `:lease_duration` - the new lease, in seconds from now. The printer's default applies
      otherwise.
    * `:charset`, `:language`, `:attributes` and `:operation_attributes`, as for the other
      operations.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri, :subscription_id]

  defstruct printer_uri: nil,
            subscription_id: nil,
            lease_duration: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{}

  def new(printer_uri, subscription_id, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      subscription_id: subscription_id,
      lease_duration: Keyword.get(opts, :lease_duration),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.RenewSubscription do
  def build_request(op) do
    lease =
      if op.lease_duration,
        do: [{:integer, "notify-lease-duration", op.lease_duration}],
        else: []

    Hippy.IPP.Operation.renew_subscription()
    |> Hippy.Message.build_request(
      op,
      [{:integer, "notify-subscription-id", op.subscription_id}] ++ lease
    )
  end
end
