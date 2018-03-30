defmodule Hippy.Protocol.Operation do
  use Hippy.Protocol.Enum, %{
    print_job: 0x0002,
    print_uri: 0x0003,
    validate_job: 0x0004,
    create_job: 0x0005,
    send_document: 0x0006,
    send_uri: 0x0007,
    cancel_job: 0x0008,
    get_job_attributes: 0x0009,
    get_jobs: 0x000A,
    get_printer_attributes: 0x000B,
    hold_job: 0x000C,
    release_job: 0x000D,
    restart_job: 0x000E,
    pause_printer: 0x0010,
    resume_printer: 0x0011,
    purge_jobs: 0x0012
  }
end
