defmodule Hippy.Operation.CreatePrinterSubscriptions do
  @moduledoc """
  Subscribes to a printer's events, such as its state changing or its jobs completing.
  Collect them with `Hippy.Operation.GetNotifications`, and read the subscription's id with
  `Hippy.Message.subscriptions/1`:

      {:ok, res} =
        uri
        |> CreatePrinterSubscriptions.new(events: ["printer-state-changed", "job-completed"])
        |> Hippy.send_operation()

      [%{"notify-subscription-id" => id}] = Hippy.Message.subscriptions(res)

  Not every printer supports subscriptions: check that its `operations-supported` includes
  `:create_printer_subscription` and its `notify-pull-method-supported` includes `"ippget"`.
  CUPS does. With CUPS's default policy, only the subscription's owner can collect its
  notifications, so create it authenticated (see "Authentication" in the README).

  ## Options

    * `:events` - the events to be notified about, such as `"job-completed"` or
      `"printer-state-changed"` (see the printer's `notify-events-supported`). Defaults to
      `["job-state-changed", "printer-state-changed"]`.
    * `:pull_method` - how notifications are collected. Defaults to `"ippget"`, which means
      fetching them with `Hippy.Operation.GetNotifications`.
    * `:lease_duration` - how long the subscription lasts, in seconds, unless renewed with
      `Hippy.Operation.RenewSubscription`. The printer's default applies otherwise (a day for
      CUPS). `0` asks for as long as the printer allows.
    * `:user_data` - up to 63 bytes the printer includes in every notification.
    * `:charset` and `:language` - default to `"utf-8"` and `"en"`.
    * `:attributes`, `:operation_attributes` and `:groups` - extra attributes, as for the other
      operations. Other subscription attributes in `attributes:` (such as
      `"notify-time-interval"`) go in the subscription group.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            events: ["job-state-changed", "printer-state-changed"],
            pull_method: "ippget",
            lease_duration: nil,
            user_data: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{}

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      events: Keyword.get(opts, :events, ["job-state-changed", "printer-state-changed"]),
      pull_method: Keyword.get(opts, :pull_method, "ippget"),
      lease_duration: Keyword.get(opts, :lease_duration),
      user_data: Keyword.get(opts, :user_data),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CreatePrinterSubscriptions do
  def build_request(op) do
    Hippy.IPP.Operation.create_printer_subscription()
    |> Hippy.Message.build_request(op, [], groups: [subscription(op)])
  end

  # The subscription group: one subscription, with its template attributes.
  defp subscription(op) do
    {:subscription,
     [
       {:keyword, "notify-pull-method", op.pull_method},
       {{:set1, :keyword}, "notify-events", op.events}
     ] ++
       optional(:integer, "notify-lease-duration", op.lease_duration) ++
       optional(:octet_string, "notify-user-data", op.user_data)}
  end

  defp optional(_syntax, _name, nil), do: []
  defp optional(syntax, name, value), do: [{syntax, name, value}]
end
