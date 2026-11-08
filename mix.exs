defmodule Hippy.MixProject do
  use Mix.Project

  def project do
    [
      app: :hippy,
      version: "0.9.0-dev",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Hippy",
      source_url: "https://github.com/electricshaman/hippy",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7.5"},
      {:plug, "~> 1.20", only: :test},
      {:ex_doc, "~> 0.19", only: :dev}
    ]
  end

  defp docs do
    [
      main: "Hippy",
      groups_for_modules: [
        Sending: [Hippy],
        Operations: [Hippy.Operation, ~r/^Hippy\.Operation\./],
        Messages: [Hippy.Message, Hippy.PrintResolution],
        Errors: [Hippy.Error, Hippy.HTTPError],
        "IPP reference": [~r/^Hippy\.IPP\./]
      ]
    ]
  end

  defp description do
    """
    Hippy is an Internet Printing Protocol (IPP) client implementation in Elixir for performing
    distributed printing over HTTP. It can be used with CUPS or network printers supporting IPP.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"],
      maintainers: ["Jeff Smith"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/electricshaman/hippy"}
    ]
  end
end
