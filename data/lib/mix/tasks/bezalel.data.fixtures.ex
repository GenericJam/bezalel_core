defmodule Mix.Tasks.Bezalel.Data.Fixtures do
  @shortdoc "Cuts bezalel_core's test/fixtures/packs/{translations,scrolls}.sqlite"

  @moduledoc """
  Cuts the fixtures core's tests read from the packs built here.

      mix bezalel.data.fixtures [--pack translations|scrolls]
                                [--from DIR] [--core ../test/fixtures/packs/core.sqlite]
                                [--out DIR]

  `--from` (default `out/`) holds the built packs, `--out` (default
  `../test/fixtures/packs/`) the fixtures; without `--pack` both are cut.

    * `translations.sqlite`: every translation's metadata row, and its verses
      for exactly the references in the core fixture's `bsb_verses`. Run
      `mix bezalel.data.translations` first.
    * `scrolls.sqlite`: the passages of the works and labels the tests cite
      (`@scroll_works`, `@scroll_labels`) and the biblical readings of
      `@scroll_verses` (a reading of each kind the tools handle: preserved,
      partly and wholly reconstructed, Hebrew numbering, a verse the MT
      lacks), with their manuscripts. Run `mix bezalel.data.scrolls` first.
  """

  use Mix.Task

  alias Bezalel.Data.{Pack, Report, ScrollsPack}

  @switches [pack: :string, from: :string, core: :string, out: :string]
  @translation_columns ~w(key name abbreviation url copyright licence source_url source_sha256)a

  # Whole works: 11QMelch (lookup by column), 4QFlor (fragments), 4Q246 (Aramaic).
  @scroll_works ~w(dss_11q13 dss_4q174 dss_4q246)
  # Single labels: 1QM column 1 and fragment 3 (a column and a fragment with
  # one number), 4QShirShabbf frg. 23 i.
  @scroll_labels [{"dss_1qm", "1"}, {"dss_1qm", "f3"}, {"dss_4q405", "f23i"}]
  # Deut 32:8 (4QDeutj's 'sons of God'), Isa 53:11 (1QIsaa whole, others in
  # part), Ps 22:16 (Hebrew 22:17, 5/6ḤevPs's כארו), Deut 1:10 (wholly
  # reconstructed in 1Q5), Josh 5:0 (4QJosha's verse before 5:1, no MT
  # verse), Mal 4:1 (Hebrew 3:19).
  @scroll_verses ~w(Deu.32.8 Isa.53.11 Psa.22.16 Deu.1.10 Jos.5.0 Mal.4.1)

  @passage_columns ~w(corpus author work_key work_title reference alternate_reference
                      book_number section_number section_end editorial_heading text original_text
                      period_tags edition translation license source_url collection sort_start
                      sort_end original_language original_license translation_license)a
  @manuscript_columns ~w(siglum name site books verses reconstructed_only sort_order)a
  @verse_columns ~w(reference book chapter verse source_reference mt_verse siglum occurrence
                    locator text letters preserved_letters language)a

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    from = Keyword.get(opts, :from, "out")
    out = Keyword.get(opts, :out, "../test/fixtures/packs")

    case Keyword.get(opts, :pack) do
      nil ->
        translations(from, out, opts)
        scrolls(from, out)

      "translations" ->
        translations(from, out, opts)

      "scrolls" ->
        scrolls(from, out)

      other ->
        Mix.raise("--pack must be translations or scrolls, not #{inspect(other)}")
    end
  end

  defp translations(from_dir, out_dir, opts) do
    from = Path.join(from_dir, "translations.sqlite")
    out = Path.join(out_dir, "translations.sqlite")
    core = Keyword.get(opts, :core, "../test/fixtures/packs/core.sqlite")

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

    Pack.write(out, translations, verses, fixture_meta(from))

    for {key, rows} <- Enum.sort(verses) do
      missing = Report.compare(Enum.map(rows, & &1.reference), references).only_b

      Mix.shell().info(
        "#{out}: #{key} #{length(rows)} of #{length(references)} references" <>
          if(missing == [], do: "", else: "; no #{key} text for #{Enum.join(missing, " ")}")
      )
    end
  end

  defp scrolls(from_dir, out_dir) do
    from = Path.join(from_dir, "scrolls.sqlite")
    out = Path.join(out_dir, "scrolls.sqlite")

    label_condition =
      Enum.map_join(@scroll_labels, " OR ", fn _ -> "(work_key = ? AND section_number = ?)" end)

    passages =
      from
      |> Pack.read(
        "SELECT #{Enum.join(@passage_columns, ", ")} FROM ancient_source_passages " <>
          "WHERE work_key IN (#{placeholders(@scroll_works)}) OR #{label_condition} ORDER BY id",
        @scroll_works ++ Enum.flat_map(@scroll_labels, &Tuple.to_list/1)
      )
      |> rows(@passage_columns)

    verses =
      from
      |> Pack.read(
        "SELECT #{Enum.join(@verse_columns, ", ")} FROM dss_biblical_verses " <>
          "WHERE reference IN (#{placeholders(@scroll_verses)}) ORDER BY rowid",
        @scroll_verses
      )
      |> rows(@verse_columns)

    sigla = verses |> Enum.map(& &1.siglum) |> Enum.uniq()

    manuscripts =
      from
      |> Pack.read(
        "SELECT #{Enum.join(@manuscript_columns, ", ")} FROM dss_biblical_manuscripts " <>
          "WHERE siglum IN (#{placeholders(sigla)}) ORDER BY sort_order",
        sigla
      )
      |> rows(@manuscript_columns)

    ScrollsPack.write(out, passages, manuscripts, verses, fixture_meta(from))

    Mix.shell().info(
      "#{out}: #{length(passages)} passages, #{length(verses)} verse readings " <>
        "(#{verses |> Enum.map(& &1.reference) |> Enum.uniq() |> length()} of " <>
        "#{length(@scroll_verses)} verses), #{length(manuscripts)} manuscripts"
    )
  end

  defp rows(rows, columns), do: Enum.map(rows, &(columns |> Enum.zip(&1) |> Map.new()))

  defp placeholders(values), do: Enum.map_join(values, ", ", fn _ -> "?" end)

  defp fixture_meta(from) do
    from
    |> Pack.read("SELECT key, value FROM pack_meta")
    |> Map.new(&List.to_tuple/1)
    |> Map.drop(~w(pack description tables sqlite_version))
    |> Map.put("fixture", "cut by bezalel_core data/: mix bezalel.data.fixtures")
  end
end
