defmodule Hippy.IPP.DelimiterTag do
  use Hippy.IPP.Enum, %{
    operation_attributes: 0x01,
    job_attributes: 0x02,
    end_of_attributes: 0x03,
    printer_attributes: 0x04,
    unsupported_attributes: 0x05,
    subscription_attributes: 0x06,
    event_notification_attributes: 0x07,
    resource_attributes: 0x08,
    document_attributes: 0x09,
    system_attributes: 0x0A
  }
end
