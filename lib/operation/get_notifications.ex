defmodule Hippy.Operation.GetNotifications do
  @moduledoc """
  Collects the notifications for one or more subscriptions created with
  `Hippy.Operation.CreatePrinterSubscriptions` or `Hippy.Operation.CreateJobSubscriptions`.
  Read them with `Hippy.Message.events/1`:

      {:ok, res} = uri |> GetNotifications.new([id], sequence_numbers: [next]) |> Hippy.send_operation()

      Hippy.Message.events(res)
      #=> [%{"notify-subscribed-event" => "job-completed", "notify-sequence-number" => 3, ...}]

  Each event has a `notify-sequence-number`. Ask for the ones after the last you've seen with
  `:sequence_numbers` (one per subscription), or you'll get every event the printer still
  holds. The response's `notify-get-interval` operation attribute (see
  `Hippy.Message.operation_attributes/1`) suggests how many seconds to wait before asking again.

  ## Options

    * `:sequence_numbers` - for each subscription, the lowest sequence number to return.
    * `:wait` - asks the printer to hold the request until there's an event. Printers may
      ignore it: CUPS answers straight away.
    * `:charset` and `:language` - default to `"utf-8"` and `"en"`.
    * `:attributes` and `:operation_attributes` - extra attributes, as for the other operations.
  """

  @def_charset "utf-8"
  @def_lang "en"

  @enforce_keys [:printer_uri, :subscription_ids]

  defstruct printer_uri: nil,
            subscription_ids: [],
            sequence_numbers: nil,
            wait: nil,
            charset: @def_charset,
            language: @def_lang,
            operation_attributes: [],
            groups: [],
            attributes: %{}

  def new(printer_uri, subscription_ids, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      subscription_ids: List.wrap(subscription_ids),
      sequence_numbers: opts |> Keyword.get(:sequence_numbers) |> wrap(),
      wait: Keyword.get(opts, :wait),
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      operation_attributes: Keyword.get(opts, :operation_attributes, []),
      groups: Keyword.get(opts, :groups, []),
      attributes: Keyword.get(opts, :attributes, %{})
    }
  end

  defp wrap(nil), do: nil
  defp wrap(value), do: List.wrap(value)
end

defimpl Hippy.Operation, for: Hippy.Operation.GetNotifications do
  def build_request(op) do
    Hippy.IPP.Operation.get_notifications()
    |> Hippy.Message.build_request(
      op,
      [{{:set1, :integer}, "notify-subscription-ids", op.subscription_ids}] ++
        optional({:set1, :integer}, "notify-sequence-numbers", op.sequence_numbers) ++
        optional(:boolean, "notify-wait", op.wait)
    )
  end

  defp optional(_syntax, _name, nil), do: []
  defp optional(syntax, name, value), do: [{syntax, name, value}]
end
