defmodule Mix.Tasks.Bezalel.Data.Fixtures do
  @shortdoc "Cuts bezalel_core's test/fixtures/packs/translations.sqlite"

  @moduledoc """
  Cuts the `translations` fixture core's tests read: every translation's
  metadata row, and its verses for exactly the references in the core
  fixture's `bsb_verses`.

      mix bezalel.data.fixtures [--from out/translations.sqlite]
                                [--core ../test/fixtures/packs/core.sqlite]
                                [--out ../test/fixtures/packs/translations.sqlite]

  Run `mix bezalel.data.net` first; `--from` is its output.
  """

  use Mix.Task

  alias Bezalel.Data.{Pack, Report}

  @switches [from: :string, core: :string, out: :string]
  @translation_columns ~w(key name abbreviation url copyright licence source_url source_sha256)a

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    from = Keyword.get(opts, :from, "out/translations.sqlite")
    core = Keyword.get(opts, :core, "../test/fixtures/packs/core.sqlite")
    out = Keyword.get(opts, :out, "../test/fixtures/packs/translations.sqlite")

    references = core |> Pack.read("SELECT reference FROM bsb_verses") |> List.flatten()
    wanted = MapSet.new(references)

    translations =
      from
      |> Pack.read(
        "SELECT #{Enum.join(@translation_columns, ", ")} FROM translations ORDER BY key"
      )
      |> Enum.map(&(@translation_columns |> Enum.zip(&1) |> Map.new()))

    verses =
      Map.new(translations, fn %{key: key} ->
        rows =
          from
          |> Pack.read(
            "SELECT reference, book, chapter, verse, text FROM translation_verses " <>
              "WHERE translation = ? ORDER BY rowid",
            [key]
          )
          |> Enum.filter(fn [reference | _rest] -> MapSet.member?(wanted, reference) end)
          |> Enum.map(&(~w(reference book chapter verse text)a |> Enum.zip(&1) |> Map.new()))

        {key, rows}
      end)

    meta =
      from
      |> Pack.read("SELECT key, value FROM pack_meta")
      |> Map.new(&List.to_tuple/1)
      |> Map.put("fixture", "cut by bezalel_core data/: mix bezalel.data.fixtures")

    Pack.write(out, translations, verses, meta)

    for {key, rows} <- Enum.sort(verses) do
      missing = Report.compare(Enum.map(rows, & &1.reference), references).only_b

      Mix.shell().info(
        "#{out}: #{key} #{length(rows)} of #{length(references)} references" <>
          if(missing == [], do: "", else: "; no #{key} text for #{Enum.join(missing, " ")}")
      )
    end
  end
end
