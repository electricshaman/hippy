defmodule Hippy.EncoderTest do
  use ExUnit.Case

  alias Hippy.{Encoder, Operation}

  test "job attributes are encoded in a job attributes group" do
    bin =
      Operation.PrintJob.new("http://localhost:631/printers/p", "DOC")
      |> Operation.build_request()
      |> Map.put(:request_id, 1)
      |> Encoder.encode()

    orientation = Hippy.IPP.Orientation.portrait()

    assert String.ends_with?(
             bin,
             <<0x02, 0x23, 21::16, "orientation-requested", 4::16, orientation::32, 0x03, "DOC">>
           )
  end

  test "requests without job attributes have no job attributes group" do
    bin =
      Operation.GetPrinterAttributes.new("http://localhost:631/printers/p")
      |> Operation.build_request()
      |> Map.put(:request_id, 1)
      |> Encoder.encode()

    assert String.ends_with?(bin, <<"ipp://localhost:631/printers/p", 0x03>>)
  end

  test "requests start with the common operation attributes" do
    req =
      Operation.CancelJob.new("https://localhost/printers/p", 7,
        charset: "us-ascii",
        language: "fr"
      )
      |> Operation.build_request()

    assert req.operation_attributes == [
             {:charset, "attributes-charset", "us-ascii"},
             {:natural_language, "attributes-natural-language", "fr"},
             {:uri, "printer-uri", "ipps://localhost/printers/p"},
             {:integer, "job-id", 7}
           ]
  end

  test "requests without a request id are rejected" do
    assert_raise ArgumentError, ~r/request_id is required/, fn ->
      Encoder.encode(%Hippy.Request{operation_id: 0x0B})
    end
  end

  test "requests built by hand default to no document" do
    bin = Encoder.encode(%Hippy.Request{operation_id: 0x0B, request_id: 1})
    assert bin == <<1, 1, 0x0B::16, 1::32, 0x01, 0x03>>
  end

  test "which-jobs atoms are encoded as hyphenated keywords" do
    req =
      Operation.GetJobs.new("http://localhost:631/printers/p", which_jobs: :not_completed)
      |> Operation.build_request()

    assert {:keyword, "which-jobs", "not-completed"} in req.operation_attributes
  end
end

defmodule Hippy.EncoderValuesTest do
  use ExUnit.Case, async: true

  alias Hippy.{Decoder, Encoder, PrintResolution}

  # Requests and responses share a layout, so the decoder can read back what the encoder wrote.
  defp round_trip(attributes) do
    req = %Hippy.Request{operation_id: 0x02, request_id: 1, operation_attributes: attributes}
    Decoder.decode(Encoder.encode(req)).operation_attributes
  end

  test "every value syntax round-trips through the decoder" do
    media_col =
      {:collection, "media-col",
       %{
         "media-size" =>
           {:collection,
            %{"x-dimension" => {:integer, 21000}, "y-dimension" => {:integer, 29700}}},
         "media-type" => {:keyword, "stationery"}
       }}

    assert round_trip([
             {:integer, "copies", -2},
             {:enum, "x-unregistered-enum", 4},
             {:boolean, "ipp-attribute-fidelity", true},
             {:boolean, "x-false", false},
             {:keyword, "sides", "two-sided-long-edge"},
             {:mime_media_type, "document-format", "application/pdf"},
             {:text_without_language, "job-message", "hello ✓"},
             {:name_without_language, "job-name", ""},
             {:text_with_language, "x-text", {"fr", "bonjour"}},
             {:name_with_language, "x-name", {"de", "Hallo"}},
             {:octet_string, "x-octets", <<0, 255>>},
             {:uri_scheme, "x-scheme", "ipps"},
             {:range_of_integer, "page-ranges", 1..5},
             {:resolution, "printer-resolution", PrintResolution.new(600, 300, :dpi)},
             media_col
           ]) == [
             {:integer, "copies", -2},
             {:enum, "x-unregistered-enum", 4},
             {:boolean, "ipp-attribute-fidelity", true},
             {:boolean, "x-false", false},
             {:keyword, "sides", "two-sided-long-edge"},
             {:mime_media_type, "document-format", "application/pdf"},
             {:text_without_language, "job-message", "hello ✓"},
             {:name_without_language, "job-name", ""},
             {:text_with_language, "x-text", {"fr", "bonjour"}},
             {:name_with_language, "x-name", {"de", "Hallo"}},
             {:octet_string, "x-octets", <<0, 255>>},
             {:uri_scheme, "x-scheme", "ipps"},
             {:range_of_integer, "page-ranges", 1..5},
             {:resolution, "printer-resolution", PrintResolution.new(600, 300, :dpi)},
             {:collection, "media-col",
              %{
                "media-size" =>
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 21000},
                     "y-dimension" => {:integer, nil, 29700}
                   }},
                "media-type" => {:keyword, nil, "stationery"}
              }}
           ]
  end

  test "out-of-band values ignore the value" do
    assert round_trip([
             {:delete_attribute, "job-hold-until", nil},
             {:no_value, "job-name", "ignored"},
             {:not_settable, "printer-name", nil}
           ]) == [
             {:delete_attribute, "job-hold-until", :delete_attribute},
             {:no_value, "job-name", :no_value},
             {:not_settable, "printer-name", :not_settable}
           ]
  end

  test "URIs accept strings and URI structs" do
    assert [{:uri, "a", %URI{host: "h"}}, {:uri, "b", %URI{host: "h"}}] =
             round_trip([{:uri, "a", "ipp://h/p"}, {:uri, "b", URI.parse("ipp://h/p")}])
  end

  test "date-times keep their time and offset" do
    {:ok, dt, _} = DateTime.from_iso8601("2026-10-29T13:45:07.300-04:00")
    [{:datetime, "x-time", decoded}] = round_trip([{:datetime, "x-time", dt}])

    assert DateTime.compare(decoded, dt) == :eq
  end

  test "lists encode multi-valued attributes and members" do
    assert round_trip([
             {:keyword, "finishings-x", ["a", "b"]},
             {{:set1, :integer}, "x-ints", [1, 2, 3]},
             {:collection, "x-cols",
              [%{"m" => {:keyword, "1"}}, %{"m" => {:keyword, ["2", "3"]}}]}
           ]) == [
             {:keyword, "finishings-x", ["a", "b"]},
             {:integer, "x-ints", [1, 2, 3]},
             {:collection, "x-cols",
              [
                %{"m" => {:keyword, nil, "1"}},
                %{"m" => [{:keyword, nil, "2"}, {:keyword, nil, "3"}]}
              ]}
           ]
  end

  test "values that can't be encoded raise" do
    for {attribute, message} <- [
          {{:integer, "copies", "2"}, ~s(cannot encode "2" as :integer for attribute "copies")},
          {{:keyword, "sides", :two_sided}, ~s(cannot encode :two_sided as :keyword)},
          {{:bogus, "x", "y"}, "unknown attribute syntax :bogus"},
          {{:keyword, :sides, "x"}, "invalid attribute"},
          {{:collection, "c", %{"m" => "x"}}, ~s(invalid value "x" for member "m" of "c")}
        ] do
      assert_raise ArgumentError, ~r/#{Regex.escape(message)}/, fn -> round_trip([attribute]) end
    end
  end
end
