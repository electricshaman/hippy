defmodule Hippy.MixProject do
  use Mix.Project

  def project do
    [
      app: :hippy,
      version: "0.4.0-dev",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Hippy",
      source_url: "https://github.com/mpichette/hippy"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.8"},
      {:ex_doc, "~> 0.23", only: :dev},
      {:hexate, ">= 0.6.1"}
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
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Jeff Smith"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/mpichette/hippy"}
    ]
  end
end
