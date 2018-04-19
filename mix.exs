defmodule Hippy.MixProject do
  use Mix.Project

  def project do
    [
      app: :hippy,
      version: "0.1.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Hippy",
      source_url: "https://github.com/electricshaman/hippy"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.0"},
      {:ex_doc, "~> 0.18", only: :dev}
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
      links: %{"GitHub" => "https://github.com/electricshaman/hippy"}
    ]
  end
end
