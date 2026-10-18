defmodule BezalelData.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezalel_data,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      # Book codes and the pack conventions the study tools read.
      {:bezalel_core, path: ".."},
      # Downloads (pinned by sha256 in pins.json).
      {:req, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false}
    ]
  end
end
