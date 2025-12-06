defmodule NsaiGateway.MixProject do
  use Mix.Project

  def project do
    [
      app: :nsai_gateway,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Unified API Gateway for North Shore AI services",
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {NsaiGateway.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.14"},
      {:plug_cowboy, "~> 2.6"},
      {:req, "~> 0.4"},
      {:joken, "~> 2.6"},
      {:hammer, "~> 6.1"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/North-Shore-AI/nsai_gateway"}
    ]
  end
end
