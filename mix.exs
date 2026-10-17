defmodule BezalelCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezalel_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # The study packs are read with Exqlite directly (Bezalel.Study.DB).
      {:exqlite, "~> 0.42"},
      # The tool behaviour every study tool implements (Rho.Tool).
      {:rho, "~> 0.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # First thing in a fresh clone: deps and the repo's git hooks (.githooks).
      setup: ["deps.get", "cmd git config core.hooksPath .githooks"]
    ]
  end
end
