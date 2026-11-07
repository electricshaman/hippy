defmodule Hippy.PrinterTest do
  use ExUnit.Case, async: true

  doctest Hippy.Printer

  alias Hippy.Printer

  defp printer(state, reasons, accepting \\ true) do
    %{
      "printer-state" => state,
      "printer-state-reasons" => reasons,
      "printer-is-accepting-jobs" => accepting
    }
  end

  test "ready when accepting, not stopped, and nothing stops it printing" do
    assert Printer.ready?(printer(:idle, ["none"]))
    assert Printer.ready?(printer(:processing, ["none"]))
    assert Printer.ready?(printer(:idle, ["toner-low-report", "media-low-warning"]))

    # Without a suffix, a reason is a warning unless the printer is stopped (RFC 8011).
    assert Printer.ready?(printer(:idle, ["media-low"]))
  end

  test "not ready when stopped, not accepting jobs, or reporting an error" do
    refute Printer.ready?(printer(:stopped, ["paused"]))
    refute Printer.ready?(printer(:idle, ["none"], false))
    refute Printer.ready?(printer(:idle, ["media-jam-error"]))
    refute Printer.ready?(printer(:idle, ["toner-low-report", "door-open-error"]))

    # CUPS reports offline-report when it can't reach a printer.
    refute Printer.ready?(printer(:idle, ["offline-report"]))
  end

  test "a single reason (not a list) works too" do
    assert Printer.ready?(printer(:idle, "none"))
    refute Printer.ready?(printer(:idle, "media-empty-error"))
  end

  test "raises when the attributes it needs weren't requested" do
    assert_raise ArgumentError, ~r/needs printer-state/, fn ->
      Printer.ready?(%{"printer-name" => "p"})
    end
  end
end

defmodule Hippy.SafeToResendTest do
  use ExUnit.Case, async: true

  test "errors where the job definitely wasn't accepted" do
    for error <- [
          %Hippy.Error{status: :server_error_not_accepting_jobs},
          %Hippy.Error{status: :client_error_not_found},
          %Hippy.HTTPError{status: 401},
          %Hippy.HTTPError{status: 426},
          %Req.TransportError{reason: :econnrefused},
          %Req.TransportError{reason: :nxdomain},
          %Req.TransportError{reason: {:tls_alert, {:bad_certificate, ~c"selfsigned_peer"}}},
          {:unknown_operation, :print_everything},
          :printer_uri_required
        ] do
      assert Hippy.safe_to_resend?(error), inspect(error)
    end
  end

  test "errors where the job may have been accepted" do
    for error <- [
          %Req.TransportError{reason: :timeout},
          %Req.TransportError{reason: :closed},
          %Hippy.HTTPError{status: 500},
          %Hippy.HTTPError{status: 502},
          %RuntimeError{message: "something else"},
          :something_else
        ] do
      refute Hippy.safe_to_resend?(error), inspect(error)
    end
  end
end
