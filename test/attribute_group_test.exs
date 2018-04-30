defmodule Hippy.AttributeGroupTest do
  use ExUnit.Case

  alias Hippy.PrintResolution

  test "to_map produces operation_attributes map without syntax tuples" do
    response = %Hippy.Response{
      data: "",
      job_attributes: [],
      operation_attributes: [
        {:charset, "attributes-charset", "utf-8"},
        {:natural_language, "attributes-natural-language", "en"}
      ]
    }

    assert Hippy.AttributeGroup.to_map(response.operation_attributes) == %{
             "attributes-charset" => "utf-8",
             "attributes-natural-language" => "en"
           }
  end

  test "to_map produces printer_attributes map without syntax tuples" do
    response = %Hippy.Response{
      data: "",
      job_attributes: [],
      operation_attributes: [
        {:charset, "attributes-charset", "utf-8"},
        {:natural_language, "attributes-natural-language", "en"}
      ],
      printer_attributes: [
        {:uri, "printer-uri-supported",
         [
           %URI{
             authority: "192.168.1.164:631",
             fragment: nil,
             host: "192.168.1.164",
             path: "/ipp/print",
             port: 631,
             query: nil,
             scheme: "ipp",
             userinfo: nil
           },
           %URI{
             authority: "192.168.1.164:443",
             fragment: nil,
             host: "192.168.1.164",
             path: "/ipp/print",
             port: 443,
             query: nil,
             scheme: "ipps",
             userinfo: nil
           }
         ]},
        {:keyword, "uri-security-supported", ["none", "tls"]},
        {:keyword, "uri-authentication-supported",
         ["requesting-user-name", "requesting-user-name"]},
        {:name_without_language, "printer-name", "NPI28C344"},
        {:text_without_language, "printer-location", ""},
        {:uri, "printer-more-info",
         %URI{
           authority: "192.168.1.164",
           fragment: nil,
           host: "192.168.1.164",
           path: "/hp/device/info_config_AirPrint.html",
           port: 80,
           query: "tab=Networking&menu=AirPrintStatus",
           scheme: "http",
           userinfo: nil
         }},
        {:text_without_language, "printer-info", "HP Color LaserJet MFP M477fdw"},
        {:text_without_language, "printer-make-and-model", "HP Color LaserJet MFP M477fdw"},
        {:enum, "printer-state", :idle},
        {:keyword, "printer-state-reasons", "wifi-not-configured-report"},
        {:text_without_language, "printer-state-message", ""},
        {:integer, "printer-state-change-time", 0},
        {:datetime, "printer-state-change-date-time",
         {:error, {:invalid_format, {1, 1, 1, 1, 1, 1, 1, "+", 1, 1}}}},
        {:keyword, "ipp-versions-supported", ["1.0", "1.1", "2.0"]},
        {:keyword, "ipp-features-supported", "airprint-1.4"},
        {:enum, "operations-supported",
         [
           :print_job,
           :print_uri,
           :validate_job,
           :create_job,
           :send_document,
           :send_uri,
           :cancel_job,
           :get_job_attributes,
           :get_jobs,
           :get_printer_attributes,
           :identify_printer
         ]},
        {:boolean, "multiple-document-jobs-supported", false},
        {:integer, "multiple-operation-time-out", 120},
        {:keyword, "multiple-operation-time-out-action", "abort-job"},
        {:charset, "charset-configured", "utf-8"},
        {:charset, "charset-supported", ["utf-8", "us-ascii"]},
        {:natural_language, "natural-language-configured", "en"},
        {:natural_language, "generated-natural-language-supported", "en"},
        {:mime_media_type, "document-format-default", "application/pdf"},
        {:mime_media_type, "document-format-supported",
         [
           "image/urf",
           "application/pdf",
           "application/postscript",
           "application/vnd.hp-PCL",
           "application/vnd.hp-PCLXL",
           "application/PCLm",
           "application/octet-stream",
           "image/jpeg"
         ]},
        {:uri_scheme, "reference-uri-schemes-supported", ["http", "https"]},
        {:boolean, "printer-is-accepting-jobs", true},
        {:integer, "queued-job-count", 0},
        {:keyword, "pdl-override-supported", "attempted"},
        {:integer, "printer-up-time", 31337},
        {:keyword, "compression-supported", "none"},
        {:boolean, "color-supported", true},
        {:boolean, "page-ranges-supported", true},
        {:keyword, "job-creation-attributes-supported",
         [
           "copies",
           "finishings",
           "sides",
           "orientation-requested",
           "media",
           "print-quality",
           "printer-resolution",
           "output-bin",
           "media-col",
           "output-mode",
           "ipp-attribute-fidelity",
           "job-name",
           "page-ranges",
           "multiple-document-handling",
           "pdf-fit-to-page",
           "print-scaling",
           "print-color-mode",
           "print-content-optimize",
           "manual-duplex-sheet-count",
           "margins-pre-applied",
           "pclm-source-resolution"
         ]},
        {:keyword, "media-supported",
         [
           "na_letter_8.5x11in",
           "na_legal_8.5x14in",
           "na_executive_7.25x10.5in",
           "na_foolscap_8.5x13in",
           "na_oficio_8.5x13.4in",
           "na_index-4x6_4x6in",
           "na_index-5x8_5x8in",
           "iso_a4_210x297mm",
           "iso_a5_148x210mm",
           "iso_a6_105x148mm",
           "jis_b5_182x257mm",
           "jis_b6_128x182mm",
           "om_small-photo_100x150mm",
           "prc_16k-195x270_195x270mm",
           "prc_16k-184x260_184x260mm",
           "roc_16k_7.75x10.75in",
           "jpn_hagaki_100x148mm",
           "jpn_oufuku_148x200mm",
           "na_number-10_4.125x9.5in",
           "na_monarch_3.875x7.5in",
           "iso_b5_176x250mm",
           "iso_c5_162x229mm",
           "iso_dl_110x220mm",
           "custom_min_3x5in",
           "custom_max_8.5x14in"
         ]},
        {:collection, "media-size-supported",
         [
           %{
             "x-dimension" => {:integer, nil, 21590},
             "y-dimension" => {:integer, nil, 27940}
           },
           %{
             "x-dimension" => {:integer, nil, 21590},
             "y-dimension" => {:integer, nil, 35560}
           },
           %{
             "x-dimension" => {:integer, nil, 18415},
             "y-dimension" => {:integer, nil, 26670}
           },
           %{
             "x-dimension" => {:integer, nil, 21590},
             "y-dimension" => {:integer, nil, 33020}
           },
           %{
             "x-dimension" => {:integer, nil, 21590},
             "y-dimension" => {:integer, nil, 34036}
           },
           %{
             "x-dimension" => {:integer, nil, 10160},
             "y-dimension" => {:integer, nil, 15240}
           },
           %{
             "x-dimension" => {:integer, nil, 12700},
             "y-dimension" => {:integer, nil, 20320}
           },
           %{
             "x-dimension" => {:integer, nil, 21000},
             "y-dimension" => {:integer, nil, 29700}
           },
           %{
             "x-dimension" => {:integer, nil, 14800},
             "y-dimension" => {:integer, nil, 21000}
           },
           %{
             "x-dimension" => {:integer, nil, 10500},
             "y-dimension" => {:integer, nil, 14800}
           },
           %{
             "x-dimension" => {:integer, nil, 18200},
             "y-dimension" => {:integer, nil, 25700}
           },
           %{
             "x-dimension" => {:integer, nil, 12800},
             "y-dimension" => {:integer, nil, 18200}
           },
           %{
             "x-dimension" => {:integer, nil, 10000},
             "y-dimension" => {:integer, nil, 15000}
           },
           %{
             "x-dimension" => {:integer, nil, 19500},
             "y-dimension" => {:integer, nil, 27000}
           },
           %{
             "x-dimension" => {:integer, nil, 18400},
             "y-dimension" => {:integer, nil, 26000}
           },
           %{
             "x-dimension" => {:integer, nil, 19685},
             "y-dimension" => {:integer, nil, 27305}
           },
           %{
             "x-dimension" => {:integer, nil, 10000},
             "y-dimension" => {:integer, nil, 14800}
           },
           %{
             "x-dimension" => {:integer, nil, 14800},
             "y-dimension" => {:integer, nil, 20000}
           },
           %{
             "x-dimension" => {:integer, nil, 10477},
             "y-dimension" => {:integer, nil, 24130}
           },
           %{
             "x-dimension" => {:integer, nil, 9842},
             "y-dimension" => {:integer, nil, 19050}
           },
           %{
             "x-dimension" => {:integer, nil, 17600},
             "y-dimension" => {:integer, nil, 25000}
           },
           %{
             "x-dimension" => {:integer, nil, 16200},
             "y-dimension" => {:integer, nil, 22900}
           },
           %{
             "x-dimension" => {:integer, nil, 11000},
             "y-dimension" => {:integer, nil, 22000}
           },
           %{
             "x-dimension" => {:range_of_integer, nil, {7620, 21590}},
             "y-dimension" => {:range_of_integer, nil, {12700, 35560}}
           }
         ]},
        {:keyword, "media-default", "iso_a4_210x297mm"},
        {:keyword, "media-col-supported",
         [
           "media-size",
           "media-top-margin",
           "media-left-margin",
           "media-right-margin",
           "media-bottom-margin",
           "media-type",
           "media-source",
           "media-source-properties",
           "duplex-supported"
         ]},
        {:collection, "media-col-default",
         %{
           "duplex-supported" => {:integer, nil, 1},
           "media-bottom-margin" => {:integer, nil, 423},
           "media-left-margin" => {:integer, nil, 423},
           "media-right-margin" => {:integer, nil, 423},
           "media-size" =>
             {:collection, nil,
              %{
                "x-dimension" => {:integer, nil, 21000},
                "y-dimension" => {:integer, nil, 29700}
              }},
           "media-source" => {:keyword, nil, "auto"},
           "media-top-margin" => {:integer, nil, 423},
           "media-type" => {:name_without_language, nil, "stationery"}
         }},
        {:keyword, "media-ready", "na_letter_8.5x11in"},
        {:collection, "media-col-ready",
         %{
           "duplex-supported" => {:integer, nil, 1},
           "media-bottom-margin" => {:integer, nil, 423},
           "media-left-margin" => {:integer, nil, 423},
           "media-right-margin" => {:integer, nil, 423},
           "media-size" =>
             {:collection, nil,
              %{
                "x-dimension" => {:integer, nil, 21590},
                "y-dimension" => {:integer, nil, 27940}
              }},
           "media-source" => {:keyword, nil, "tray-2"},
           "media-top-margin" => {:integer, nil, 423},
           "media-type" => {:name_without_language, nil, "stationery"}
         }},
        {:integer, "media-left-margin-supported", 423},
        {:integer, "media-right-margin-supported", 423},
        {:integer, "media-top-margin-supported", 423},
        {:integer, "media-bottom-margin-supported", 423},
        {:keyword, "media-source-supported", ["auto", "manual", "tray-1", "tray-2"]},
        {:octet_string, "printer-input-tray",
         [
           "type=other;mediafeed=-2;mediaxfeed=-2;maxcapacity=-2;level=-2;status=0;name=auto;",
           "type=sheetFeedManual;mediafeed=-2;mediaxfeed=-2;maxcapacity=50;level=0;status=8;name=manual;",
           "type=sheetFeedAutoNonRemovableTray;mediafeed=-2;mediaxfeed=-2;maxcapacity=50;level=0;status=8;name=tray-1;",
           "type=sheetFeedAutoNonRemovableTray;mediafeed=279400;mediaxfeed=215900;maxcapacity=250;level=-3;status=0;name=tray-2;"
         ]},
        {:name_without_language, "media-type-supported",
         [
           "stationery",
           "HPMatte90gsm",
           "HPMatte105gsm",
           "HPMatte120gsm",
           "HPMatte160gsm",
           "HPCover",
           "HPGlossy130gsm",
           "photographic-glossy",
           "HPTrifoldGlossy160gsm",
           "HPGlossyPhoto",
           "stationery-lightweight",
           "extraLight",
           "intermediate",
           "midweight",
           "stationery-heavyweight",
           "extraHeavy",
           "cardstock",
           "photographic-high-gloss",
           "extraHeavyGloss",
           "cardGlossy",
           "transparency",
           "labels",
           "stationery-letterhead",
           "envelope",
           "envelope-heavyweight",
           "stationery-preprinted",
           "stationery-prepunched",
           "stationery-colored",
           "stationery-bond",
           "recycled",
           "rough",
           "heavyRough",
           "photographic-film"
         ]},
        {:collection, "job-constraints-supported",
         %{
           "media-col" =>
             {:collection, nil,
              %{
                "media-size" => [
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 16200},
                     "y-dimension" => {:integer, nil, 22900}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 9842},
                     "y-dimension" => {:integer, nil, 19050}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 14800},
                     "y-dimension" => {:integer, nil, 20000}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 10000},
                     "y-dimension" => {:integer, nil, 15000}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 10500},
                     "y-dimension" => {:integer, nil, 14800}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 12700},
                     "y-dimension" => {:integer, nil, 20320}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 10160},
                     "y-dimension" => {:integer, nil, 15240}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 14800},
                     "y-dimension" => {:integer, nil, 21000}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 12800},
                     "y-dimension" => {:integer, nil, 18200}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 10000},
                     "y-dimension" => {:integer, nil, 14800}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 10477},
                     "y-dimension" => {:integer, nil, 24130}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 17600},
                     "y-dimension" => {:integer, nil, 25000}
                   }},
                  {:collection, nil,
                   %{
                     "x-dimension" => {:integer, nil, 11000},
                     "y-dimension" => {:integer, nil, 22000}
                   }}
                ],
                "media-type" => [
                  {:name_without_language, nil, "envelope-heavyweight"},
                  {:name_without_language, nil, "labels"},
                  {:name_without_language, nil, "cardstock"},
                  {:name_without_language, nil, "HPCover"},
                  {:name_without_language, nil, "transparency"},
                  {:name_without_language, nil, "envelope"},
                  {:name_without_language, nil, "photographic-film"}
                ]
              }},
           "resolver-name" => {:name_without_language, nil, "duplex-unsupported-media"},
           "sides" => [
             {:keyword, nil, "two-sided-short-edge"},
             {:keyword, nil, "two-sided-long-edge"}
           ]
         }},
        {:collection, "job-resolvers-supported",
         %{
           "resolver-name" => {:name_without_language, nil, "duplex-unsupported-media"},
           "sides" => {:keyword, nil, "one-sided"}
         }},
        {:integer, "pages-per-minute", 28},
        {:integer, "pages-per-minute-color", 28},
        {:range_of_integer, "jpeg-k-octets-supported", 0..11719},
        {:range_of_integer, "jpeg-x-dimension-supported", 0..8192},
        {:range_of_integer, "jpeg-y-dimension-supported", 1..8192},
        {:range_of_integer, "pdf-k-octets-supported", 0..75000},
        {:keyword, "pdf-versions-supported",
         [
           "adobe-1.2",
           "adobe-1.3",
           "adobe-1.4",
           "adobe-1.5",
           "adobe-1.6",
           "adobe-1.7",
           "iso-19005-1_2005",
           "iso-32000-1_2008"
         ]},
        {:keyword, "urf-supported",
         [
           "V1.4",
           "CP99",
           "W8",
           "OB10",
           "PQ3-4-5",
           "ADOBERGB24",
           "DEVRGB24",
           "DEVW8",
           "SRGB24",
           "DM1",
           "IS1",
           "MT1-2-3-4-5-12",
           "RS600"
         ]},
        {:uri, "printer-uuid",
         %URI{
           authority: nil,
           fragment: nil,
           host: nil,
           path: "uuid:564e424b-4b35-5444-5156-f430b928c344",
           port: nil,
           query: nil,
           scheme: "urn",
           userinfo: nil
         }},
        {:name_without_language, "marker-names",
         [
           "Cyan Cartridge HP CF411A",
           "Magenta Cartridge HP CF413A",
           "Yellow Cartridge HP CF412A",
           "Black Cartridge HP CF410A"
         ]},
        {:name_without_language, "marker-colors", ["#00FFFF", "#FF00FF", "#FFFF00", "#000000"]},
        {:keyword, "marker-types", ["toner", "toner", "toner", "toner"]},
        {:integer, "marker-low-levels", '\t\t\t\a'},
        {:integer, "marker-high-levels", 'dddd'},
        {:integer, "marker-levels", ']]]_'},
        {:integer, "copies-default", 1},
        {:keyword, "multiple-document-handling-default", "single-document"},
        {:enum, "finishings-default", :none},
        {:enum, "orientation-requested-default", :portrait},
        {:enum, "print-quality-default", :normal},
        {:resolution, "printer-resolution-default", PrintResolution.new(600, 600, :dpi)},
        {:keyword, "sides-default", "one-sided"},
        {:keyword, "output-bin-default", "face-down"},
        {:keyword, "output-mode-default", "auto"},
        {:range_of_integer, "copies-supported", 1..999},
        {:keyword, "multiple-document-handling-supported",
         [
           "single-document",
           "separate-documents-uncollated-copies",
           "separate-documents-collated-copies",
           "single-document-new-sheet"
         ]},
        {:enum, "finishings-supported", :none},
        {:enum, "orientation-requested-supported",
         [:portrait, :landscape, :reverse_landscape, :reverse_portrait, :none]},
        {:enum, "print-quality-supported", [:normal, :draft]},
        {:resolution, "printer-resolution-supported", PrintResolution.new(600, 600, :dpi)},
        {:keyword, "sides-supported",
         ["one-sided", "two-sided-short-edge", "two-sided-long-edge"]},
        {:range_of_integer, "job-impressions-supported", 1..99999},
        {:range_of_integer, "job-media-sheets-supported", 1..99999},
        {:keyword, "output-bin-supported", "face-down"},
        {:octet_string, "printer-output-tray",
         "type=unRemovableBin;maxcapacity=125;remaining=-3;status=0;name=face-down;stackingorder=firstToLast;pagedelivery=faceDown;"},
        {:keyword, "output-mode-supported", ["auto", "auto-monochrome", "monochrome", "color"]},
        {:uri, "printer-icons",
         [
           %URI{
             authority: "192.168.1.164",
             fragment: nil,
             host: "192.168.1.164",
             path: "/ipp/images/printer.png",
             port: 80,
             query: nil,
             scheme: "http",
             userinfo: nil
           },
           %URI{
             authority: "192.168.1.164",
             fragment: nil,
             host: "192.168.1.164",
             path: "/ipp/images/printer-large.png",
             port: 80,
             query: nil,
             scheme: "http",
             userinfo: nil
           }
         ]},
        {:uri, "printer-supply-info-uri",
         %URI{
           authority: "192.168.1.164",
           fragment: nil,
           host: "192.168.1.164",
           path: "/hp/device/mSupplyStatus.html",
           port: 80,
           query: nil,
           scheme: "http",
           userinfo: nil
         }},
        {:text_without_language, "printer-device-id", "It's a printer"},
        {:name_without_language, "printer-dns-sd-name", "HP Color LaserJet MFP M477fdw"},
        {:unknown, "printer-geo-location", :unknown},
        {:keyword, "printer-kind", ["document", "envelope", "photo"]},
        {:enum, "landscape-orientation-requested-preferred", :reverse_landscape},
        {:name_without_language, "printer-wifi-ssid", ""},
        {:enum, "printer-wifi-state", 3},
        {:keyword, "identify-actions-default", "display"},
        {:keyword, "identify-actions-supported", "display"},
        {:keyword, "print-scaling-default", "auto"},
        {:keyword, "print-scaling-supported", ["auto", "auto-fit", "fill", "fit", "none"]},
        {:name_without_language, "printer-firmware-name", "20160921"},
        {:text_without_language, "printer-firmware-string-version", "20160921"},
        {:octet_string, "printer-firmware-version", "20160921"},
        {:keyword, "which-jobs-supported", ["completed", "not-completed"]},
        {:text_without_language, "printer-organization", ""},
        {:text_without_language, "printer-organizational-unit", ""},
        {:keyword, "printer-get-attributes-supported", "document-format"},
        {:integer, "printer-config-change-time", 0},
        {:datetime, "printer-config-change-date-time",
         {:error, {:invalid_format, {1, 1, 1, 1, 1, 1, 1, "+", 1, 1}}}},
        {:keyword, "epcl-version-supported", "epcl1.0"},
        {:keyword, "image-enhancement-supported", "object-tagging"},
        {:boolean, "manual-duplex-supported", [false, true]},
        {:keyword, "pclm-raster-back-side", "normal"},
        {:keyword, "pclm-compression-method-preferred", "flate"},
        {:resolution, "pclm-source-resolution-supported", PrintResolution.new(600, 600, :dpi)},
        {:integer, "pclm-strip-height-preferred", 64},
        {:integer, "pclm-strip-height-supported", [16, 32, 64, 128]},
        {:boolean, "pdf-fit-to-page-default", false},
        {:boolean, "pdf-fit-to-page-supported", [false, true]},
        {:integer, "pdf-size-constraints", 75_000_000},
        {:keyword, "print-color-mode-default", "auto"},
        {:keyword, "print-color-mode-supported",
         ["auto", "auto-monochrome", "monochrome", "color"]},
        {:keyword, "print-content-optimize-default", "auto"},
        {:keyword, "print-content-optimize-supported",
         ["auto", "photo", "graphics", "text", "text-and-graphics"]}
      ],
      request_id: 1,
      status_code: :successful_ok,
      unknown_attributes: [],
      version: %Hippy.IPPVersion{major: 1, minor: 1}
    }

    assert Hippy.AttributeGroup.to_map(response.printer_attributes) == %{
             "printer-uri-supported" => [
               %URI{
                 authority: "192.168.1.164:631",
                 fragment: nil,
                 host: "192.168.1.164",
                 path: "/ipp/print",
                 port: 631,
                 query: nil,
                 scheme: "ipp",
                 userinfo: nil
               },
               %URI{
                 authority: "192.168.1.164:443",
                 fragment: nil,
                 host: "192.168.1.164",
                 path: "/ipp/print",
                 port: 443,
                 query: nil,
                 scheme: "ipps",
                 userinfo: nil
               }
             ],
             "uri-security-supported" => ["none", "tls"],
             "uri-authentication-supported" => [
               "requesting-user-name",
               "requesting-user-name"
             ],
             "printer-name" => "NPI28C344",
             "printer-location" => "",
             "printer-more-info" => %URI{
               authority: "192.168.1.164",
               fragment: nil,
               host: "192.168.1.164",
               path: "/hp/device/info_config_AirPrint.html",
               port: 80,
               query: "tab=Networking&menu=AirPrintStatus",
               scheme: "http",
               userinfo: nil
             },
             "printer-info" => "HP Color LaserJet MFP M477fdw",
             "printer-make-and-model" => "HP Color LaserJet MFP M477fdw",
             "printer-state" => :idle,
             "printer-state-reasons" => "wifi-not-configured-report",
             "printer-state-message" => "",
             "printer-state-change-time" => 0,
             "printer-state-change-date-time" =>
               {:error, {:invalid_format, {1, 1, 1, 1, 1, 1, 1, "+", 1, 1}}},
             "ipp-versions-supported" => [
               "1.0",
               "1.1",
               "2.0"
             ],
             "ipp-features-supported" => "airprint-1.4",
             "operations-supported" => [
               :print_job,
               :print_uri,
               :validate_job,
               :create_job,
               :send_document,
               :send_uri,
               :cancel_job,
               :get_job_attributes,
               :get_jobs,
               :get_printer_attributes,
               :identify_printer
             ],
             "multiple-document-jobs-supported" => false,
             "multiple-operation-time-out" => 120,
             "multiple-operation-time-out-action" => "abort-job",
             "charset-configured" => "utf-8",
             "charset-supported" => [
               "utf-8",
               "us-ascii"
             ],
             "natural-language-configured" => "en",
             "generated-natural-language-supported" => "en",
             "document-format-default" => "application/pdf",
             "document-format-supported" => [
               "image/urf",
               "application/pdf",
               "application/postscript",
               "application/vnd.hp-PCL",
               "application/vnd.hp-PCLXL",
               "application/PCLm",
               "application/octet-stream",
               "image/jpeg"
             ],
             "reference-uri-schemes-supported" => [
               "http",
               "https"
             ],
             "printer-is-accepting-jobs" => true,
             "queued-job-count" => 0,
             "pdl-override-supported" => "attempted",
             "printer-up-time" => 31337,
             "compression-supported" => "none",
             "color-supported" => true,
             "page-ranges-supported" => true,
             "job-creation-attributes-supported" => [
               "copies",
               "finishings",
               "sides",
               "orientation-requested",
               "media",
               "print-quality",
               "printer-resolution",
               "output-bin",
               "media-col",
               "output-mode",
               "ipp-attribute-fidelity",
               "job-name",
               "page-ranges",
               "multiple-document-handling",
               "pdf-fit-to-page",
               "print-scaling",
               "print-color-mode",
               "print-content-optimize",
               "manual-duplex-sheet-count",
               "margins-pre-applied",
               "pclm-source-resolution"
             ],
             "media-supported" => [
               "na_letter_8.5x11in",
               "na_legal_8.5x14in",
               "na_executive_7.25x10.5in",
               "na_foolscap_8.5x13in",
               "na_oficio_8.5x13.4in",
               "na_index-4x6_4x6in",
               "na_index-5x8_5x8in",
               "iso_a4_210x297mm",
               "iso_a5_148x210mm",
               "iso_a6_105x148mm",
               "jis_b5_182x257mm",
               "jis_b6_128x182mm",
               "om_small-photo_100x150mm",
               "prc_16k-195x270_195x270mm",
               "prc_16k-184x260_184x260mm",
               "roc_16k_7.75x10.75in",
               "jpn_hagaki_100x148mm",
               "jpn_oufuku_148x200mm",
               "na_number-10_4.125x9.5in",
               "na_monarch_3.875x7.5in",
               "iso_b5_176x250mm",
               "iso_c5_162x229mm",
               "iso_dl_110x220mm",
               "custom_min_3x5in",
               "custom_max_8.5x14in"
             ],
             "media-size-supported" => [
               %{
                 "x-dimension" => 21590,
                 "y-dimension" => 27940
               },
               %{
                 "x-dimension" => 21590,
                 "y-dimension" => 35560
               },
               %{
                 "x-dimension" => 18415,
                 "y-dimension" => 26670
               },
               %{
                 "x-dimension" => 21590,
                 "y-dimension" => 33020
               },
               %{
                 "x-dimension" => 21590,
                 "y-dimension" => 34036
               },
               %{
                 "x-dimension" => 10160,
                 "y-dimension" => 15240
               },
               %{
                 "x-dimension" => 12700,
                 "y-dimension" => 20320
               },
               %{
                 "x-dimension" => 21000,
                 "y-dimension" => 29700
               },
               %{
                 "x-dimension" => 14800,
                 "y-dimension" => 21000
               },
               %{
                 "x-dimension" => 10500,
                 "y-dimension" => 14800
               },
               %{
                 "x-dimension" => 18200,
                 "y-dimension" => 25700
               },
               %{
                 "x-dimension" => 12800,
                 "y-dimension" => 18200
               },
               %{
                 "x-dimension" => 10000,
                 "y-dimension" => 15000
               },
               %{
                 "x-dimension" => 19500,
                 "y-dimension" => 27000
               },
               %{
                 "x-dimension" => 18400,
                 "y-dimension" => 26000
               },
               %{
                 "x-dimension" => 19685,
                 "y-dimension" => 27305
               },
               %{
                 "x-dimension" => 10000,
                 "y-dimension" => 14800
               },
               %{
                 "x-dimension" => 14800,
                 "y-dimension" => 20000
               },
               %{
                 "x-dimension" => 10477,
                 "y-dimension" => 24130
               },
               %{
                 "x-dimension" => 9842,
                 "y-dimension" => 19050
               },
               %{
                 "x-dimension" => 17600,
                 "y-dimension" => 25000
               },
               %{
                 "x-dimension" => 16200,
                 "y-dimension" => 22900
               },
               %{
                 "x-dimension" => 11000,
                 "y-dimension" => 22000
               },
               %{
                 "x-dimension" => {7620, 21590},
                 "y-dimension" => {12700, 35560}
               }
             ],
             "media-default" => "iso_a4_210x297mm",
             "media-col-supported" => [
               "media-size",
               "media-top-margin",
               "media-left-margin",
               "media-right-margin",
               "media-bottom-margin",
               "media-type",
               "media-source",
               "media-source-properties",
               "duplex-supported"
             ],
             "media-col-default" => %{
               "duplex-supported" => 1,
               "media-bottom-margin" => 423,
               "media-left-margin" => 423,
               "media-right-margin" => 423,
               "media-size" => %{
                 "x-dimension" => 21000,
                 "y-dimension" => 29700
               },
               "media-source" => "auto",
               "media-top-margin" => 423,
               "media-type" => "stationery"
             },
             "media-ready" => "na_letter_8.5x11in",
             "media-col-ready" => %{
               "duplex-supported" => 1,
               "media-bottom-margin" => 423,
               "media-left-margin" => 423,
               "media-right-margin" => 423,
               "media-size" => %{
                 "x-dimension" => 21590,
                 "y-dimension" => 27940
               },
               "media-source" => "tray-2",
               "media-top-margin" => 423,
               "media-type" => "stationery"
             },
             "media-left-margin-supported" => 423,
             "media-right-margin-supported" => 423,
             "media-top-margin-supported" => 423,
             "media-bottom-margin-supported" => 423,
             "media-source-supported" => [
               "auto",
               "manual",
               "tray-1",
               "tray-2"
             ],
             "printer-input-tray" => [
               "type=other;mediafeed=-2;mediaxfeed=-2;maxcapacity=-2;level=-2;status=0;name=auto;",
               "type=sheetFeedManual;mediafeed=-2;mediaxfeed=-2;maxcapacity=50;level=0;status=8;name=manual;",
               "type=sheetFeedAutoNonRemovableTray;mediafeed=-2;mediaxfeed=-2;maxcapacity=50;level=0;status=8;name=tray-1;",
               "type=sheetFeedAutoNonRemovableTray;mediafeed=279400;mediaxfeed=215900;maxcapacity=250;level=-3;status=0;name=tray-2;"
             ],
             "media-type-supported" => [
               "stationery",
               "HPMatte90gsm",
               "HPMatte105gsm",
               "HPMatte120gsm",
               "HPMatte160gsm",
               "HPCover",
               "HPGlossy130gsm",
               "photographic-glossy",
               "HPTrifoldGlossy160gsm",
               "HPGlossyPhoto",
               "stationery-lightweight",
               "extraLight",
               "intermediate",
               "midweight",
               "stationery-heavyweight",
               "extraHeavy",
               "cardstock",
               "photographic-high-gloss",
               "extraHeavyGloss",
               "cardGlossy",
               "transparency",
               "labels",
               "stationery-letterhead",
               "envelope",
               "envelope-heavyweight",
               "stationery-preprinted",
               "stationery-prepunched",
               "stationery-colored",
               "stationery-bond",
               "recycled",
               "rough",
               "heavyRough",
               "photographic-film"
             ],
             "job-constraints-supported" => %{
               "media-col" => %{
                 "media-size" => [
                   %{
                     "x-dimension" => 16200,
                     "y-dimension" => 22900
                   },
                   %{
                     "x-dimension" => 9842,
                     "y-dimension" => 19050
                   },
                   %{
                     "x-dimension" => 14800,
                     "y-dimension" => 20000
                   },
                   %{
                     "x-dimension" => 10000,
                     "y-dimension" => 15000
                   },
                   %{
                     "x-dimension" => 10500,
                     "y-dimension" => 14800
                   },
                   %{
                     "x-dimension" => 12700,
                     "y-dimension" => 20320
                   },
                   %{
                     "x-dimension" => 10160,
                     "y-dimension" => 15240
                   },
                   %{
                     "x-dimension" => 14800,
                     "y-dimension" => 21000
                   },
                   %{
                     "x-dimension" => 12800,
                     "y-dimension" => 18200
                   },
                   %{
                     "x-dimension" => 10000,
                     "y-dimension" => 14800
                   },
                   %{
                     "x-dimension" => 10477,
                     "y-dimension" => 24130
                   },
                   %{
                     "x-dimension" => 17600,
                     "y-dimension" => 25000
                   },
                   %{
                     "x-dimension" => 11000,
                     "y-dimension" => 22000
                   }
                 ],
                 "media-type" => [
                   "envelope-heavyweight",
                   "labels",
                   "cardstock",
                   "HPCover",
                   "transparency",
                   "envelope",
                   "photographic-film"
                 ]
               },
               "resolver-name" => "duplex-unsupported-media",
               "sides" => [
                 "two-sided-short-edge",
                 "two-sided-long-edge"
               ]
             },
             "job-resolvers-supported" => %{
               "resolver-name" => "duplex-unsupported-media",
               "sides" => "one-sided"
             },
             "pages-per-minute" => 28,
             "pages-per-minute-color" => 28,
             "jpeg-k-octets-supported" => 0..11719,
             "jpeg-x-dimension-supported" => 0..8192,
             "jpeg-y-dimension-supported" => 1..8192,
             "pdf-k-octets-supported" => 0..75000,
             "pdf-versions-supported" => [
               "adobe-1.2",
               "adobe-1.3",
               "adobe-1.4",
               "adobe-1.5",
               "adobe-1.6",
               "adobe-1.7",
               "iso-19005-1_2005",
               "iso-32000-1_2008"
             ],
             "urf-supported" => [
               "V1.4",
               "CP99",
               "W8",
               "OB10",
               "PQ3-4-5",
               "ADOBERGB24",
               "DEVRGB24",
               "DEVW8",
               "SRGB24",
               "DM1",
               "IS1",
               "MT1-2-3-4-5-12",
               "RS600"
             ],
             "printer-uuid" => %URI{
               authority: nil,
               fragment: nil,
               host: nil,
               path: "uuid:564e424b-4b35-5444-5156-f430b928c344",
               port: nil,
               query: nil,
               scheme: "urn",
               userinfo: nil
             },
             "marker-names" => [
               "Cyan Cartridge HP CF411A",
               "Magenta Cartridge HP CF413A",
               "Yellow Cartridge HP CF412A",
               "Black Cartridge HP CF410A"
             ],
             "marker-colors" => [
               "#00FFFF",
               "#FF00FF",
               "#FFFF00",
               "#000000"
             ],
             "marker-types" => [
               "toner",
               "toner",
               "toner",
               "toner"
             ],
             "marker-low-levels" => '\t\t\t\a',
             "marker-high-levels" => 'dddd',
             "marker-levels" => ']]]_',
             "copies-default" => 1,
             "multiple-document-handling-default" => "single-document",
             "finishings-default" => :none,
             "orientation-requested-default" => :portrait,
             "print-quality-default" => :normal,
             "printer-resolution-default" => PrintResolution.new(600, 600, :dpi),
             "sides-default" => "one-sided",
             "output-bin-default" => "face-down",
             "output-mode-default" => "auto",
             "copies-supported" => 1..999,
             "multiple-document-handling-supported" => [
               "single-document",
               "separate-documents-uncollated-copies",
               "separate-documents-collated-copies",
               "single-document-new-sheet"
             ],
             "finishings-supported" => :none,
             "orientation-requested-supported" => [
               :portrait,
               :landscape,
               :reverse_landscape,
               :reverse_portrait,
               :none
             ],
             "print-quality-supported" => [:normal, :draft],
             "printer-resolution-supported" => PrintResolution.new(600, 600, :dpi),
             "sides-supported" => ["one-sided", "two-sided-short-edge", "two-sided-long-edge"],
             "job-impressions-supported" => 1..99999,
             "job-media-sheets-supported" => 1..99999,
             "output-bin-supported" => "face-down",
             "printer-output-tray" =>
               "type=unRemovableBin;maxcapacity=125;remaining=-3;status=0;name=face-down;stackingorder=firstToLast;pagedelivery=faceDown;",
             "output-mode-supported" => ["auto", "auto-monochrome", "monochrome", "color"],
             "printer-icons" => [
               %URI{
                 authority: "192.168.1.164",
                 fragment: nil,
                 host: "192.168.1.164",
                 path: "/ipp/images/printer.png",
                 port: 80,
                 query: nil,
                 scheme: "http",
                 userinfo: nil
               },
               %URI{
                 authority: "192.168.1.164",
                 fragment: nil,
                 host: "192.168.1.164",
                 path: "/ipp/images/printer-large.png",
                 port: 80,
                 query: nil,
                 scheme: "http",
                 userinfo: nil
               }
             ],
             "printer-supply-info-uri" => %URI{
               authority: "192.168.1.164",
               fragment: nil,
               host: "192.168.1.164",
               path: "/hp/device/mSupplyStatus.html",
               port: 80,
               query: nil,
               scheme: "http",
               userinfo: nil
             },
             "printer-device-id" => "It's a printer",
             "printer-dns-sd-name" => "HP Color LaserJet MFP M477fdw",
             "printer-geo-location" => :unknown,
             "printer-kind" => [
               "document",
               "envelope",
               "photo"
             ],
             "landscape-orientation-requested-preferred" => :reverse_landscape,
             "printer-wifi-ssid" => "",
             "printer-wifi-state" => 3,
             "identify-actions-default" => "display",
             "identify-actions-supported" => "display",
             "print-scaling-default" => "auto",
             "print-scaling-supported" => [
               "auto",
               "auto-fit",
               "fill",
               "fit",
               "none"
             ],
             "printer-firmware-name" => "20160921",
             "printer-firmware-string-version" => "20160921",
             "printer-firmware-version" => "20160921",
             "which-jobs-supported" => [
               "completed",
               "not-completed"
             ],
             "printer-organization" => "",
             "printer-organizational-unit" => "",
             "printer-get-attributes-supported" => "document-format",
             "printer-config-change-time" => 0,
             "printer-config-change-date-time" =>
               {:error, {:invalid_format, {1, 1, 1, 1, 1, 1, 1, "+", 1, 1}}},
             "epcl-version-supported" => "epcl1.0",
             "image-enhancement-supported" => "object-tagging",
             "manual-duplex-supported" => [
               false,
               true
             ],
             "pclm-raster-back-side" => "normal",
             "pclm-compression-method-preferred" => "flate",
             "pclm-source-resolution-supported" => PrintResolution.new(600, 600, :dpi),
             "pclm-strip-height-preferred" => 64,
             "pclm-strip-height-supported" => [16, 32, 64, 128],
             "pdf-fit-to-page-default" => false,
             "pdf-fit-to-page-supported" => [false, true],
             "pdf-size-constraints" => 75_000_000,
             "print-color-mode-default" => "auto",
             "print-color-mode-supported" => [
               "auto",
               "auto-monochrome",
               "monochrome",
               "color"
             ],
             "print-content-optimize-default" => "auto",
             "print-content-optimize-supported" => [
               "auto",
               "photo",
               "graphics",
               "text",
               "text-and-graphics"
             ]
           }
  end

  test "to_map produces job_attributes map without syntax tuples" do
    response = %Hippy.Response{
      data: "",
      job_attributes: [
        [
          {:integer, "number-of-documents", 0},
          {:integer, "job-media-progress", 0},
          {:uri, "job-more-info",
           %URI{
             authority: "localhost:631",
             fragment: nil,
             host: "localhost",
             path: "/jobs/59",
             port: 631,
             query: nil,
             scheme: "http",
             userinfo: nil
           }},
          {:boolean, "job-preserved", false},
          {:integer, "job-printer-up-time", 31337},
          {:uri, "job-printer-uri",
           %URI{
             authority: "localhost:631",
             fragment: nil,
             host: "localhost",
             path: "/printers/atlantis",
             port: 631,
             query: nil,
             scheme: "ipp",
             userinfo: nil
           }},
          {:uri, "job-uri",
           %URI{
             authority: "localhost:631",
             fragment: nil,
             host: "localhost",
             path: "/jobs/59",
             port: 631,
             query: nil,
             scheme: "ipp",
             userinfo: nil
           }},
          {:uri, "printer-uri",
           %URI{
             authority: "localhost:631",
             fragment: nil,
             host: "localhost",
             path: "/printers/atlantis",
             port: 631,
             query: nil,
             scheme: "ipp",
             userinfo: nil
           }},
          {:name_without_language, "InputSlot", "Auto"},
          {:integer, "number-up", 1},
          {:name_without_language, "job-sheets", "none"},
          {:name_without_language, "cupsPrintQuality", "4"},
          {:name_without_language, "PageSize", "Letter"},
          {:boolean, "Collate", true},
          {:integer, "job-priority", 50},
          {:name_without_language, "ColorModel", "Grayscale"},
          {:name_without_language, "Duplex", "DuplexNoTumble"},
          {:mime_media_type, "document-format-detected", "application/pdf"},
          {:mime_media_type, "document-format", "application/pdf"},
          {:uri, "job-uuid",
           %URI{
             authority: nil,
             fragment: nil,
             host: nil,
             path: "uuid:1c56f5a4-6c58-3f01-5e18-3867e0db1f9a",
             port: nil,
             query: nil,
             scheme: "urn",
             userinfo: nil
           }},
          {:datetime, "date-time-at-completed", 31337},
          {:datetime, "date-time-at-creation", 31337},
          {:datetime, "date-time-at-processing", 31337},
          {:integer, "time-at-completed", 31337},
          {:integer, "time-at-creation", 31337},
          {:integer, "time-at-processing", 1_523_226_391},
          {:integer, "job-id", 59},
          {:enum, "job-state", :completed},
          {:keyword, "job-state-reasons", "processing-to-stop-point"},
          {:integer, "job-impressions-completed", 5},
          {:integer, "job-media-sheets-completed", 5},
          {:integer, "job-k-octets", 73},
          {:keyword, "job-hold-until", "no-hold"},
          {:text_without_language, "job-printer-state-message", ""},
          {:keyword, "job-printer-state-reasons", "none"}
        ]
      ],
      operation_attributes: [
        {:charset, "attributes-charset", "utf-8"},
        {:natural_language, "attributes-natural-language", "en"}
      ],
      printer_attributes: [],
      request_id: 3,
      status_code: :successful_ok,
      unknown_attributes: [],
      version: %Hippy.IPPVersion{major: 1, minor: 1}
    }

    assert Hippy.AttributeGroup.to_map(response.job_attributes) == %{
             "number-of-documents" => 0,
             "job-media-progress" => 0,
             "job-more-info" => %URI{
               authority: "localhost:631",
               fragment: nil,
               host: "localhost",
               path: "/jobs/59",
               port: 631,
               query: nil,
               scheme: "http",
               userinfo: nil
             },
             "job-preserved" => false,
             "job-printer-up-time" => 31337,
             "job-printer-uri" => %URI{
               authority: "localhost:631",
               fragment: nil,
               host: "localhost",
               path: "/printers/atlantis",
               port: 631,
               query: nil,
               scheme: "ipp",
               userinfo: nil
             },
             "job-uri" => %URI{
               authority: "localhost:631",
               fragment: nil,
               host: "localhost",
               path: "/jobs/59",
               port: 631,
               query: nil,
               scheme: "ipp",
               userinfo: nil
             },
             "printer-uri" => %URI{
               authority: "localhost:631",
               fragment: nil,
               host: "localhost",
               path: "/printers/atlantis",
               port: 631,
               query: nil,
               scheme: "ipp",
               userinfo: nil
             },
             "InputSlot" => "Auto",
             "number-up" => 1,
             "job-sheets" => "none",
             "cupsPrintQuality" => "4",
             "PageSize" => "Letter",
             "Collate" => true,
             "job-priority" => 50,
             "ColorModel" => "Grayscale",
             "Duplex" => "DuplexNoTumble",
             "document-format-detected" => "application/pdf",
             "document-format" => "application/pdf",
             "job-uuid" => %URI{
               authority: nil,
               fragment: nil,
               host: nil,
               path: "uuid:1c56f5a4-6c58-3f01-5e18-3867e0db1f9a",
               port: nil,
               query: nil,
               scheme: "urn",
               userinfo: nil
             },
             "date-time-at-completed" => 31337,
             "date-time-at-creation" => 31337,
             "date-time-at-processing" => 31337,
             "time-at-completed" => 31337,
             "time-at-creation" => 31337,
             "time-at-processing" => 1_523_226_391,
             "job-id" => 59,
             "job-state" => :completed,
             "job-state-reasons" => "processing-to-stop-point",
             "job-impressions-completed" => 5,
             "job-media-sheets-completed" => 5,
             "job-k-octets" => 73,
             "job-hold-until" => "no-hold",
             "job-printer-state-message" => "",
             "job-printer-state-reasons" => "none"
           }
  end
end
