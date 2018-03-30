# Hippy

Hippy is an [Internet Printing Protocol](https://en.wikipedia.org/wiki/Internet_Printing_Protocol)  (IPP) client implementation for performing distributed printing over HTTP.  In addition to printing documents, IPP also supports a number of other operations such as retrieving print job status, pausing jobs, resuming jobs, etc.

[CUPS](https://en.wikipedia.org/wiki/CUPS) provides a standard IPP server out of the box, though some higher-end networked printers are capable of providing their own server.  Testing at this early stage has been primarily against CUPS.

Note: This is currently very alpha-stage software and will be evolving quickly.  Please only consider it for production use at your own risk.

## Installation

The package can be installed by adding `hippy` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hippy, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/hippy](https://hexdocs.pm/hippy).

