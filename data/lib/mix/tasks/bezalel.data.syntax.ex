defmodule Mix.Tasks.Bezalel.Data.Syntax do
  @shortdoc "Builds out/syntax.sqlite from Clear-Bible MACULA's syntax trees"

  @moduledoc """
  Builds the `syntax` pack: each verse's clause structure from MACULA
  Hebrew (the WLC) and MACULA Greek (the SBLGNT) lowfat syntax trees.

      mix bezalel.data.syntax [--core PATH] [--out DIR]

  Fetches the files `pins.json` → `macula` names (their sha256s in
  `macula_files.json`) into `work/macula/{hebrew,greek}/`, checking each,
  and writes `DIR/syntax.sqlite` (default `out/`) and
  `DIR/syntax_report.txt`.

  The verse numbers are mapped from the editions' numbering (the WLC's is
  the Hebrew Bible's) to the packs' English one with the base core pack's
  `verses.reference` (`Bezalel.Data.Download.base_core!/1`: `--core PATH`,
  else base.json's pack downloaded into `work/base/`).
  """

  use Mix.Task

  alias Bezalel.Data.{Books, Download, Net, Pack, Syntax, SyntaxPack}

  @switches [core: :string, out: :string]
  @base Path.expand("../../../base.json", __DIR__)

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    {:ok, _apps} = Application.ensure_all_started(:req)

    pin = Download.pin!("macula")
    shas = Syntax.pinned_files(pin)
    paths = fetch(pin, shas)

    core = Download.base_core!(opts[:core])

    core_rows = Pack.read(core, "SELECT reference, book, chapter, verse FROM verses")
    english = Syntax.english_numbering(core_rows)

    Mix.shell().info("Reading #{length(paths)} MACULA files…")

    parsed =
      paths
      |> Task.async_stream(&read(&1, english), ordered: true, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    verses = verse_rows(parsed)
    editions = editions(pin)
    out = Keyword.get(opts, :out, "out")
    path = Path.join(out, "syntax.sqlite")

    SyntaxPack.write(path, editions, verses, %{
      "built_by" => "bezalel_core data/: mix bezalel.data.syntax",
      "licences" =>
        "MACULA Hebrew Linguistic Datasets and MACULA Greek Linguistic Datasets © 2022-2024 " <>
          "Biblica, Inc: CC BY 4.0, https://creativecommons.org/licenses/by/4.0/ (syntax trees: " <>
          "Westminster Hebrew Syntax, Groves Center, CC BY 4.0; Hebrew morphology: OpenScriptures " <>
          "Hebrew Bible, CC BY 4.0; Hebrew English glosses: Cherith, CC BY 4.0; WLC text: public " <>
          "domain; SBLGNT text: CC BY 4.0, Society of Biblical Literature and Logos Bible " <>
          "Software; Greek English glosses: Berean Interlinear Bible, public domain, and " <>
          "Cherith, CC BY 4.0). Not imported: the UBS data MACULA uses by permission (" <>
          Enum.join(Syntax.not_licensed(), ", ") <>
          ") and the Hebrew gloss attribute (SIL's SILHA glosses, an SIL licence, not CC BY)",
      "build_sha256" => Syntax.build_digest(),
      "macula_sha256" => Syntax.source_digest(shas),
      "macula_source" => Syntax.source(pin),
      "versification" =>
        "WLC (Hebrew) to English numbering from the base core pack's verses.reference",
      "core_sha256" => base_core()["raw_sha256"]
    })

    core_verses = core_rows |> Enum.map(fn [_, b, c, v] -> "#{b}.#{c}.#{v}" end) |> Enum.uniq()

    report =
      Syntax.report(%{
        source: Syntax.source(pin),
        parsed: parsed,
        verses: verses,
        core_verses: core_verses
      })

    File.write!(Path.join(out, "syntax_report.txt"), report)
    bytes = File.read!(path)

    Mix.shell().info(
      "Wrote #{path}: #{length(verses)} verses, #{byte_size(bytes)} bytes, " <>
        "sha256 #{Net.sha256(bytes)}\nReport: #{Path.join(out, "syntax_report.txt")}"
    )
  end

  defp fetch(pin, shas) do
    results =
      for {{language, name}, sha256} <- Enum.sort_by(shas, &elem(&1, 0)) do
        path = Path.join(["work", "macula", language, name])

        {language, name, path,
         Download.fetch(pin[language]["url"] <> name, path, &check(&1, sha256))}
      end

    case for {_, name, _, {:error, message}} <- results, do: "#{name}: #{message}" do
      [] -> for {language, name, path, _} <- results, do: {language, name, path}
      errors -> Mix.raise("MACULA files differ from pins.json:\n" <> Enum.join(errors, "\n"))
    end
  end

  defp check(bytes, expected) do
    case Net.sha256(bytes) do
      ^expected -> :ok
      actual -> {:error, "sha256 #{actual}, pinned #{inspect(expected)}"}
    end
  end

  defp read({language, name, path}, english) do
    pin = Download.pin!("macula")
    parsed = Syntax.parse(File.read!(path), language)
    file = "#{pin[language]["path"]}/#{name}"

    parsed.sentences
    |> Syntax.rows(file, english)
    |> Map.merge(%{
      language: language,
      file: file,
      sentences: length(parsed.sentences),
      attribute_counts: parsed.attribute_counts
    })
  end

  # One row per English verse: the sentences of every file that touch it.
  defp verse_rows(parsed) do
    edition = Map.new(parsed, &{&1.file, Syntax.editions()[&1.language].edition})

    parsed
    |> Enum.flat_map(& &1.rows)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {{book, chapter, verse}, rows} ->
      sources = rows |> Enum.flat_map(&elem(&1, 2)) |> Enum.uniq() |> Enum.sort()
      files = rows |> Enum.map(&elem(&1, 3)) |> Enum.uniq()

      %{
        reference: "#{book}.#{chapter}.#{verse}",
        book: book,
        chapter: chapter,
        verse: verse,
        edition: edition[hd(files)],
        source_reference: Enum.map_join(sources, " ", fn {b, c, v} -> "#{b}.#{c}.#{v}" end),
        source_files: Enum.join(files, " "),
        clauses: rows |> Enum.map(&elem(&1, 1)) |> Jason.encode!()
      }
    end)
    |> Enum.sort_by(&{Books.index(&1.book), &1.chapter, &1.verse})
  end

  defp editions(pin) do
    for {language, %{edition: edition, language: name}} <- Enum.sort(Syntax.editions()) do
      %{
        edition: edition,
        language: name,
        name: "MACULA #{name} (#{edition})",
        repo: pin[language]["repo"],
        commit_sha: pin[language]["commit"],
        licence: "CC BY 4.0",
        attribution: pin[language]["attribution"]
      }
    end
  end

  defp base_core, do: @base |> File.read!() |> Jason.decode!() |> get_in(["packs", "core"])
end
