# Changelog

## Unreleased

### Fixes

- Multi-valued attributes (e.g. `job-state-reasons`, `job-sheets`) are now decoded as a list in
  every attribute group. Previously only printer attributes were, so `AttributeGroup.to_map/2`
  kept only the last value for job and operation attributes.
- Values of a multi-valued attribute with different syntaxes (e.g. `keyword` and `name`) are kept
  together in one attribute instead of being split by syntax.
- Attributes repeated by name within a group (which some printers send) are merged in every group,
  dropping duplicate values.

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
