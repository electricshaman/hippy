# Changelog

## Unreleased

### Breaking changes

- Attributes and collection members the IANA registry defines as sets (`1setOf`) are always
  lists in `AttributeGroup.to_map/1` and the `Hippy.Response` map helpers, even with a single
  value. For example `Hippy.Response.job(res)["job-state-reasons"]` is now `["none"]` rather
  than `"none"`, and `finishings-col`'s `folding` member is a list of collections.
  Before, the type depended on how many values the printer sent. Attributes the registry
  doesn't know, and out-of-band values such as `:no_value`, are unchanged, and so are the
  tuples in `Hippy.Response`'s fields.
- `Hippy.Response.printer_attributes` is now a list of groups, one per printer, like
  `job_attributes`. Responses with several printers, such as CUPS-Get-Printers, used to be
  flattened into one group, with each attribute's values combined into a list across printers,
  so there was no reliable way to tell which value belonged to which printer. Code reading
  `printer_attributes` directly needs to take the first group (or use `Hippy.Response.printer/1`).
  `AttributeGroup.to_map(res.printer_attributes)` still returns the first printer's map.
- Value tags Hippy doesn't know now decode as `{tag, name, bytes}`, keeping the tag number and
  raw bytes. Before, some were relabelled (e.g. as `:charset`, `:octet_string`, `:integer` or
  `:out_of_band`), which lost the tag. Values that don't fit their tag (e.g. an integer that
  isn't 4 bytes) are kept the same way.
- `Hippy.Response.printer/1` returns `nil` instead of an empty map when there is no printer, like
  `Hippy.Response.job/1`.

### Added

- `Hippy.IPP.Attributes` describes every attribute in the IANA IPP registry: its value types
  (with ranges and length limits), whether it can have several values, the groups it belongs
  to, whether it's deprecated or obsolete, and, for collections, its members.
- `raw: true` on `Hippy.Decoder.decode/2`, `Hippy.send_operation/2` and
  `Hippy.Server.send_request/3` returns the response exactly as it was sent: one tuple per
  value, values as on the wire (enums and the status code as integers, URIs as strings, dates as
  tuples, …) and collections as ordered member lists. `Hippy.Encoder.encode/1` accepts all of
  these, and encoding a raw response's groups again gives the original bytes.
- Requests can carry other attribute groups: `Hippy.Request` has a `groups` field, an ordered
  list of `{tag, attributes}` (e.g. `{:printer_attributes, [...]}` for CUPS-Add-Modify-Printer,
  or one `{:subscription_attributes, [...]}` per subscription), encoded after the operation and
  job attributes. Every operation accepts a `groups:` option, e.g. a subscription group on
  Print-Job to be notified about the job.
- `Hippy.Operation.CupsGetPrinters`, `CupsGetClasses` and `CupsGetDefault`, for listing the
  printers and classes on a CUPS server and getting its default printer. They take the server's
  URI (e.g. `"ipp://localhost:631/"`) and CUPS's filters (`limit:`, `first_printer_name:`,
  `printer_location:`, `printer_type:`/`printer_type_mask:`).
- Operations addressed to the server rather than a printer: an operation with a `server_uri`
  field instead of `printer_uri` is sent to that URI, and `Hippy.Request.new/4` leaves out the
  `printer-uri` attribute for it.
- `Hippy.Response.printers/1` returns a map per printer.

### Fixes

- A status code Hippy doesn't know (e.g. a vendor one) is kept as an integer instead of
  raising `Hippy.ValueError` and losing the whole response.

## 0.5.1 (2026-10-30)

### Fixes

- Responses with several printer attribute groups (such as CUPS-Get-Printers, one group per
  printer) keep every printer's values again, so the combined lists stay aligned by position.
  0.5.0 dropped repeated values across printers (regression in 0.5.0).

## 0.5.0 (2026-10-29)

### Breaking changes

- Multi-valued attributes are now lists in every attribute group. Previously only printer
  attributes were, and job and operation attributes such as `job-state-reasons` kept only their
  last value, so code expecting a single value there may now get a list.
- `Hippy.Operation.build_request/1` no longer sets `request_id`. `Hippy.Server` assigns one when
  sending, unless it's already set. `Hippy.Encoder.encode/1` raises `ArgumentError` for a
  request without one, so code that encodes requests directly needs to set it.
- An `https://` printer URI is now sent as `ipps://` in the `printer-uri` attribute instead of
  `ipp://`.
- Enum values are now checked against the IANA IPP registry, which changes how some values
  decode:
  - `printer-wifi-state` is decoded (e.g. `:off`, `:on`, `:not_configured`) instead of being
    left as an integer.
  - `Hippy.IPP.Finishing.fold_accordian` is now `fold_accordion`, as in the registry, so
    finishing 90 decodes to `:fold_accordion`. `fold_accordian/0` still works but is deprecated.
  - Newly supported enum attributes (see Added) decode to atoms instead of integers.
- `Hippy.IPP.JobState` no longer has a `nil` state for the value 0, which isn't a job state in
  RFC 8011. A `job-state` of 0 is now left as the integer 0, like other unknown enum values.

### Deprecated

- The `Hippy.Protocol.*` modules are renamed to `Hippy.IPP.*` (e.g. `Hippy.IPP.Orientation`,
  `use Hippy.IPP.Enum`), so they aren't confused with Elixir protocols. The old names still work
  but warn at compile time with the new name, and will be removed in a later release.
  `Hippy.Protocol.Binary` was unused and is deprecated with no replacement.

### Added

- All operations accept `operation_attributes:`, and Print-Job accepts `job_attributes:`, for
  sending any attribute. Each replaces an attribute of the same name that Hippy would otherwise
  send, so defaults such as `orientation-requested` can be overridden.
- Print-Job accepts `document_format:` (e.g. `"application/pdf"`).
- The encoder supports every IPP value syntax: `boolean`, `mimeMediaType`, text and name with or
  without language, `octetString`, `uriScheme`, `dateTime`, `rangeOfInteger`, `resolution`,
  collections and out-of-band values (e.g. `{:delete_attribute, "job-hold-until", nil}`), as
  well as multi-valued attributes given as lists.
- `Hippy.send_operation/2` and `Hippy.Server.send_request/3` accept `req_options:` for one
  request, merged over `config :hippy, req_options: [...]`, so printers with different
  credentials or TLS settings can be used at the same time. `send_operation/2` also accepts
  `endpoint:`. Passing the endpoint URL as the second argument still works.
- `Hippy.Response.job/1`, `jobs/1`, `printer/1`, `operation/1` and `unsupported/1` return
  attributes as maps, e.g. `Hippy.Response.job(res)["job-id"]`.
- `ipps://` printer URIs are supported.
- Enum modules for `document-state`, `system-state`, `resource-state`, `power-state`,
  `client-type` and `transmission-status`, and decoding of the attributes the registry defines
  in terms of other enums: `input-orientation-requested`, `image-orientation`,
  `media-source-feed-orientation`, `input-quality`, `output-device-job-states`, `fetch-status-code`
  and `start-`/`end-`/`request-power-state`.
- `Hippy.IPP.Operation` has every operation in the IANA registry (66 more, including document,
  resource and system operations).
- `Hippy.Response` has `subscription_attributes`, `event_notification_attributes`,
  `resource_attributes`, `document_attributes` and `system_attributes` fields, and
  `unknown_attributes` now holds attributes from group tags IANA hasn't assigned.
- `Hippy.Request.new/4` builds a request with the common operation attributes
  (`attributes-charset`, `attributes-natural-language`, `printer-uri`), for implementing
  operations.
- `Hippy.Request` now defaults `data` to an empty binary, so requests built by hand without a
  document can be encoded.

### Fixes

- Responses with subscription, event notification, resource, document or system attribute
  groups, with `not-settable`, `delete-attribute` or `admin-define` values, or with value tags
  reserved for future use no longer crash the decoder.
- `ipp://` URIs without a port now connect to IPP's default port 631 instead of port 80.
- Setting `headers:` in `req_options` no longer drops the `application/ipp` content type.
- `Hippy.Encoder.encode/1` raises `ArgumentError` for an attribute it can't encode, instead of
  crashing with an unrelated error.
- Values of a multi-valued attribute with different syntaxes (e.g. `keyword` and `name`) are kept
  together in one attribute instead of being split by syntax.
- Attributes repeated by name within a group (which some printers send) are merged in every group,
  dropping duplicate values.

### Other

- The README documents authentication, self-signed certificates (including pinning a
  certificate, since Erlang won't trust a self-signed one through `cacertfile`) and timeouts.
- CI runs the tests on the oldest and newest supported Elixir/OTP versions, and the CUPS
  integration tests on master and on PRs labelled `cups`.
- The enum values are checked against a copy of the IANA IPP registry, refreshed with
  `mix run scripts/update_ipp_registry.exs`.

## 0.4.1 (2026-10-29)

### Added

- Enum decoding can be extended with `config :hippy, enums: %{"attribute-name" => Module}`.
  Registered enums take precedence over the built-in ones. See `Hippy.Protocol.Enum`.
- `Hippy.Protocol.Enum` is now a behaviour, so enum modules that don't use the macro (such as a
  bit field) can be registered too.
- `xxx-default` and `xxx-supported` attributes are decoded with the enum for `xxx` when they have
  no enum of their own.

### Fixes

- Decoding a response containing `printer-wifi-state` no longer crashes (regression in 0.4.0).
- `printer-type` is decoded into a list of capability descriptions again (regression in 0.4.0).

## 0.4.0 (2026-10-28)

### Breaking changes

- Elixir 1.15 or later is now required.
- The HTTP client is now [Req](https://hex.pm/packages/req) instead of HTTPoison.
  Transport errors are returned as Req exceptions (e.g. `{:error, %Req.TransportError{}}`)
  instead of `{:error, %HTTPoison.Error{}}`.
- Non-200 HTTP responses now return `{:error, {:http_error, status, body}}` instead of
  `{:ok, %HTTPoison.Response{}}`.
- Enum attributes or values Hippy doesn't recognize (e.g. vendor extensions) are now left as
  integers instead of raising `Hippy.EnumError` / `Hippy.ValueError`.

### Fixes

- Job attributes (e.g. `orientation-requested` on Print-Job) are now sent in the job
  attributes group instead of the operation attributes group.
- `which_jobs: :not_completed` is now encoded as the IPP keyword `"not-completed"`.
- Responses containing an unsupported-attributes group no longer crash; the attributes are
  available in the new `Hippy.Response.unsupported_attributes` field.
- `textWithLanguage` and `nameWithLanguage` values are now decoded, as
  `{language, text}` tuples.
- Multi-valued collection members and repeated attribute groups keep their order.
- `Hippy.AttributeGroup.to_map/2` returns `{:error, :bad_attribute_group}` for an
  out-of-range index instead of crashing.

### Other

- Resolves hackney security advisories (including EEF-CVE-2026-115693) by dropping hackney.
- Extra Req options can be set with `config :hippy, req_options: [...]`.
