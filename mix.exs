defmodule BezalelCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezalel_core,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  # test/support: the in-memory materials store the tests configure.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # The study packs are read with Exqlite directly (Bezalel.Study.DB).
      {:exqlite, "~> 0.42"},
      # The tool behaviour every study tool implements (Rho.Tool), the
      # session shape Bezalel.Library.Transcript reads, attachments by
      # reference (Bezalel.Materials, rho 0.2), consults and attributed
      # model messages (Bezalel.Agent.Pushback, rho 0.3), pictures on the
      # ChatGPT sign-in (Rho.Images, rho 0.4).
      sibling(:rho, "~> 0.4"),
      # Bezalel.Materials: a file's media type from its name, and back.
      {:mime, "~> 2.0"},
      # Bezalel.Agent.Reply encodes tool arguments for the TOOL CALL block.
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false}
    ]
  end

  # BEZALEL_LOCAL_DEPS uses sibling checkouts (../rho) instead of Hex, for
  # working on them, as the phone app does: 1 (or true) for all, or a
  # comma-separated list of apps.
  defp sibling(app, requirement) do
    if local_dep?(app),
      do: {app, path: "../#{app}", override: true},
      else: {app, requirement}
  end

  defp local_dep?(app) do
    case System.get_env("BEZALEL_LOCAL_DEPS") do
      nil -> false
      all when all in ["1", "true"] -> true
      apps -> Atom.to_string(app) in String.split(apps, ",", trim: true)
    end
  end

  defp aliases do
    [
      # First thing in a fresh clone: deps and the repo's git hooks (.githooks).
      setup: ["deps.get", "cmd git config core.hooksPath .githooks"]
    ]
  end
end
