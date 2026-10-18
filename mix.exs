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
      # reference (Bezalel.Materials). Pinned to a commit until rho's next
      # release has attachments by reference; then {:rho, "~> 0.2"}.
      sibling(:rho, "GenericJam/rho", "b27e0251ec9decac3c1cf50f90ecfe171f154500"),
      # Bezalel.Materials: a file's media type from its name, and back.
      {:mime, "~> 2.0"},
      # Bezalel.Agent.Reply encodes tool arguments for the TOOL CALL block.
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false}
    ]
  end

  # BEZALEL_LOCAL_DEPS uses sibling checkouts (../rho) instead of the pins,
  # for working on them, as the phone app does: 1 (or true) for all, or a
  # comma-separated list of apps.
  defp sibling(app, repo, ref) do
    if local_dep?(app),
      do: {app, path: "../#{app}", override: true},
      else: {app, github: repo, ref: ref}
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
