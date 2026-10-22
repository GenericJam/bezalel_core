defmodule Mix.Tasks.Bezalel.Data.Witnesses do
  @shortdoc "Builds out/witnesses.sqlite: the Samaritan Pentateuch, the SBLGNT and its apparatus, HOTTP"

  @moduledoc """
  Builds the `witnesses` pack (`Bezalel.Data.Witnesses`):

      mix bezalel.data.witnesses [--core PATH] [--out DIR]

  Fetches the files `pins.json` names under `sp` (DT-UCPH/sp Text-Fabric
  features), `sblgnt` (Faithlife/SBLGNT text and apparatus) and `hottp`
  (ubsicap/ubs-open-license) into `work/{sp,sblgnt,hottp}/`, checking each
  against its sha256, and writes `DIR/witnesses.sqlite` (default `out/`)
  and `DIR/witnesses_report.txt`.

  The Hebrew-numbered sources (the Samaritan Pentateuch, HOTTP) are mapped to
  the packs' English numbering with the base core pack's
  `verses.reference`, and the SBLGNT's verses checked against its
  `verses`: `--core PATH`, else `base.json`'s core pack downloaded into
  `work/base/` (`Bezalel.Data.Download.base_core!/1`).
  """

  use Mix.Task

  alias Bezalel.Data.{Books, Download, Pack, Witnesses, WitnessesPack}

  @switches [core: :string, out: :string]
  @base Path.expand("../../../base.json", __DIR__)

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    {:ok, _apps} = Application.ensure_all_started(:req)

    sp_pin = Download.pin!("sp")
    sblgnt_pin = Download.pin!("sblgnt")
    hottp_pin = Download.pin!("hottp")

    sp = fetch(sp_pin["url"], sp_pin["files"], "sp")
    text = fetch(sblgnt_pin["url"], sblgnt_pin["text"], "sblgnt")
    app = fetch(sblgnt_pin["url"], sblgnt_pin["apparatus"], "sblgnt")
    hottp = fetch(hottp_pin["url"], hottp_pin["files"], "hottp")

    core = Download.base_core!(opts[:core])
    core_rows = Pack.read(core, "SELECT reference, book, chapter, verse FROM verses")
    english = core_rows |> Enum.map(&hd/1) |> Witnesses.english_numbering()

    Mix.shell().info("Reading the Samaritan Pentateuch…")
    samaritan = Witnesses.samaritan(&Map.fetch!(sp, &1), english)

    Mix.shell().info("Reading the SBLGNT and its apparatus…")
    sblgnt = text |> by_stem() |> Witnesses.sblgnt_text()
    apparatus = app |> by_stem() |> Witnesses.apparatus()

    Mix.shell().info("Reading HOTTP…")
    entries = Witnesses.hottp(hottp["HOTTP.XML"], english)
    ratings = Witnesses.ratings(hottp["HOTTP-RATINGS-EN.HTML"])
    factors = Witnesses.factors(hottp["HOTTP-FACTORS-EN.HTML"])

    nt = Witnesses.nt_verses(core_rows)
    sblgnt_keys = MapSet.new(sblgnt, &{&1.book, &1.chapter, &1.verse})
    torah = torah_references(core_rows)
    sp_references = MapSet.new(samaritan.verses, & &1.reference)

    sources =
      sources(sp_pin, sblgnt_pin, hottp_pin, %{sp: sp, text: text, app: app, hottp: hottp})

    out = Keyword.get(opts, :out, "out")
    path = Path.join(out, "witnesses.sqlite")

    WitnessesPack.write(
      path,
      %{
        "witness_sources" => sources,
        "sp_verses" => samaritan.verses,
        "sblgnt_verses" => sblgnt,
        "sblgnt_apparatus" => apparatus.units,
        "hottp_entries" => entries.entries,
        "hottp_alternatives" => entries.alternatives,
        "hottp_verses" => entries.verses,
        "hottp_ratings" => ratings,
        "hottp_factors" => factors
      },
      %{
        "built_by" => "bezalel_core data/: mix bezalel.data.witnesses",
        "licences" =>
          Enum.map_join(
            sources,
            "; ",
            &"#{&1.name} (#{&1.tables}): #{&1.licence}, #{&1.licence_url}"
          ),
        "build_sha256" => Witnesses.build_digest(),
        "sp_source" => source_url(sources, "sp"),
        "sp_sha256" => Witnesses.digest(sp_pin["files"]),
        "sblgnt_source" => source_url(sources, "sblgnt"),
        "sblgnt_sha256" =>
          Witnesses.digest(Map.merge(sblgnt_pin["text"], sblgnt_pin["apparatus"])),
        "hottp_source" => source_url(sources, "hottp"),
        "hottp_sha256" => Witnesses.digest(hottp_pin["files"]),
        "versification" =>
          "Samaritan Pentateuch and HOTTP: Hebrew to English numbering from the base core pack's " <>
            "verses.reference; SBLGNT: its own numbering, the core pack's verses numbering",
        "core_sha256" => base_core()["raw_sha256"]
      }
    )

    report =
      Witnesses.report(%{
        sources: Enum.map(sources, &"#{&1.name}: #{&1.source_url} (digest #{&1.source_sha256})"),
        sp: samaritan,
        sp_missing: torah |> Enum.reject(&MapSet.member?(sp_references, &1)),
        sblgnt: sblgnt,
        sblgnt_extra:
          for(
            %{book: b, chapter: c, verse: v} = row <- sblgnt,
            {b, c, v} not in nt,
            do: row.reference
          ),
        sblgnt_missing:
          for(
            {b, c, v} <- Enum.sort_by(nt, &order/1),
            {b, c, v} not in sblgnt_keys,
            do: "#{b}.#{c}.#{v}"
          ),
        apparatus: apparatus,
        hottp: entries,
        ratings: ratings,
        factors: factors
      })

    File.write!(Path.join(out, "witnesses_report.txt"), report)
    bytes = File.read!(path)

    Mix.shell().info(
      "Wrote #{path}: #{length(samaritan.verses)} SP verses, #{length(sblgnt)} SBLGNT verses, " <>
        "#{length(apparatus.units)} apparatus notes (#{length(apparatus.refused)} unparsed), " <>
        "#{length(entries.entries)} HOTTP entries, #{byte_size(bytes)} bytes, " <>
        "sha256 #{Witnesses.sha256(bytes)}\nReport: #{Path.join(out, "witnesses_report.txt")}"
    )
  end

  defp sources(sp_pin, sblgnt_pin, hottp_pin, files) do
    digest = fn map ->
      map
      |> Map.new(fn {name, bytes} -> {name, Witnesses.sha256(bytes)} end)
      |> Witnesses.digest()
    end

    [
      %{
        key: "sp",
        name: "The Samaritan Pentateuch (DT-UCPH/sp, Text-Fabric #{sp_pin["tag"]})",
        tables: "sp_verses",
        licence: "CC BY-NC 4.0",
        licence_url: "https://creativecommons.org/licenses/by-nc/4.0/",
        attribution:
          "Christian Canu Højgaard, Martijn Naaijer and Stefan Schorch, Text-Fabric Dataset of the " <>
            "Samaritan Pentateuch (Zenodo, 2023, doi:10.5281/zenodo.7734632); the text of MS Dublin " <>
            "Chester Beatty Library 751 and MS Garizim 1 as transcribed by the Samaritanus project " <>
            "(Stefan Schorch, Halle)",
        source_url: "#{sp_pin["repo"]}/tree/#{sp_pin["commit"]}/#{sp_pin["path"]}",
        source_sha256: digest.(files.sp)
      },
      %{
        key: "sblgnt",
        name: "The SBL Greek New Testament (Faithlife/SBLGNT)",
        tables: "sblgnt_verses",
        licence: "CC BY 4.0",
        licence_url: "https://creativecommons.org/licenses/by/4.0/",
        attribution:
          "The SBL Greek New Testament, copyright 2010 by the Society of Biblical Literature and " <>
            "Logos Bible Software",
        source_url: "#{sblgnt_pin["repo"]}/tree/#{sblgnt_pin["commit"]}/data/sblgnt/text",
        source_sha256: digest.(files.text)
      },
      %{
        key: "sblgnt_apparatus",
        name: "The SBLGNT apparatus (Faithlife/SBLGNT)",
        tables: "sblgnt_apparatus",
        licence: "CC BY 4.0",
        licence_url: "https://creativecommons.org/licenses/by/4.0/",
        attribution:
          "Apparatus for the SBL Greek New Testament, copyright 2010 by the Society of Biblical " <>
            "Literature and Logos Bible Software",
        source_url: "#{sblgnt_pin["repo"]}/tree/#{sblgnt_pin["commit"]}/data/sblgntapp/xml",
        source_sha256: digest.(files.app)
      },
      %{
        key: "hottp",
        name: "The UBS Hebrew Old Testament Text Project (HOTTP)",
        tables: "hottp_entries hottp_alternatives hottp_verses hottp_ratings hottp_factors",
        licence: "CC BY-SA 4.0",
        licence_url: "https://creativecommons.org/licenses/by-sa/4.0/",
        attribution:
          "Preliminary and Interim Report on the Hebrew Old Testament Text Project, © United Bible " <>
            "Societies 1973-1980, 2003-2023",
        source_url: "#{hottp_pin["repo"]}/tree/#{hottp_pin["commit"]}/#{hottp_pin["path"]}",
        source_sha256: digest.(files.hottp)
      }
    ]
  end

  defp source_url(sources, key), do: Enum.find(sources, &(&1.key == key)).source_url

  # A source's files by their stem: 'data/sblgnt/text/John.txt' → 'John'.
  defp by_stem(files),
    do: Map.new(files, fn {path, bytes} -> {Path.basename(path) |> Path.rootname(), bytes} end)

  # The core pack's Torah verses by English reference ('Exo.8.1(7.26)' is Exo.8.1).
  defp torah_references(rows) do
    for [reference, book, _, _] <- rows, book in ~w(Gen Exo Lev Num Deu), uniq: true do
      reference |> String.split("(") |> hd()
    end
  end

  defp order({book, chapter, verse}),
    do: {Books.index(book), chapter, verse}

  defp fetch(url, pinned, dir) do
    results =
      for {name, sha256} <- pinned do
        {name, Download.fetch(url <> name, Path.join(["work", dir, name]), &check(&1, sha256))}
      end

    case for {name, {:error, message}} <- results, do: "#{name}: #{message}" do
      [] -> Map.new(results, fn {name, {:ok, bytes}} -> {name, bytes} end)
      errors -> Mix.raise("#{dir} files differ from pins.json:\n" <> Enum.join(errors, "\n"))
    end
  end

  defp check(bytes, expected) do
    case Witnesses.sha256(bytes) do
      ^expected -> :ok
      actual -> {:error, "sha256 #{actual}, pinned #{inspect(expected)}"}
    end
  end

  defp base_core, do: @base |> File.read!() |> Jason.decode!() |> get_in(["packs", "core"])
end
