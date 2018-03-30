defmodule Hippy.ServerTest do
  use ExUnit.Case

  alias Hippy.{Server, Operation.GetJobs}

  test "nil printer_uri in operation returns an error when using send_operation/1" do
    op = %GetJobs{printer_uri: nil}
    {:error, :printer_uri_required} = Server.send_operation(op)
  end

  test "nil endpoint returns an error when using send_operation/2" do
    op = %GetJobs{printer_uri: "http://valid"}
    {:error, :printer_uri_required} = Server.send_operation(op, nil)
  end
end
