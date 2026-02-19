defmodule Bandeira.MixProject do
  use Mix.Project

  def project do
    [
      app: :bandeira,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Official Elixir client SDK for Bandeira feature flag service",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/felipekafuri/bandeira-sdks"
      }
    ]
  end
end
