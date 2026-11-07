defmodule Hippy.Printer do
  @moduledoc """
  Functions for printer attributes, as returned by `Hippy.Message.printer/1` and
  `Hippy.Message.printers/1`.
  """

  @doc """
  Returns whether a printer can take a job now.

  It's ready when it's accepting jobs (`printer-is-accepting-jobs`), isn't stopped
  (`printer-state`), and none of its `printer-state-reasons` stops it printing:

    * reasons ending in `-error`, such as `media-jam-error`, stop it;
    * `-warning` and `-report` reasons, such as `toner-low-report`, don't;
    * a reason without a suffix, such as `media-empty`, is an error only while the printer is
      stopped (RFC 8011, section 5.4.12), so it doesn't count separately;
    * reasons starting with `offline`, which CUPS reports (as `offline-report`) when it can't
      reach a printer, also stop it, though RFC 8011 doesn't define them.

  The map must include those three attributes; ask for them with `requested_attributes:`.

      iex> Hippy.Printer.ready?(%{
      ...>   "printer-state" => :idle,
      ...>   "printer-state-reasons" => ["toner-low-report"],
      ...>   "printer-is-accepting-jobs" => true
      ...> })
      true
  """
  def ready?(%{"printer-state" => state, "printer-is-accepting-jobs" => accepting} = printer) do
    reasons = printer |> Map.get("printer-state-reasons", ["none"]) |> List.wrap()

    accepting == true and state != :stopped and not Enum.any?(reasons, &blocking?/1)
  end

  def ready?(printer) do
    raise ArgumentError,
          "ready?/1 needs printer-state, printer-state-reasons and printer-is-accepting-jobs, got: " <>
            inspect(Map.keys(printer))
  end

  defp blocking?(reason) when is_binary(reason),
    do: String.ends_with?(reason, "-error") or String.starts_with?(reason, "offline")

  defp blocking?(_reason), do: false
end
