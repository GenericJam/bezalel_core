defmodule Mix.Tasks.Bezalel.Data.Dictionaries do
  @shortdoc "Builds out/dictionaries.sqlite from the UBS open-licence dictionaries"

  @moduledoc """
  Builds the `dictionaries` pack: the UBS Dictionary of Biblical Hebrew and
  the UBS Dictionary of the Greek New Testament (ubsicap/ubs-open-license,
  CC BY-SA 4.0), English.

      mix bezalel.data.dictionaries [--core PATH] [--out DIR]

  Fetches the files `pins.json` → `ubs_dictionaries` names into `work/ubs/`,
  checking each against its sha256 and each README for the licence and
  attribution, and writes `DIR/dictionaries.sqlite` (default `out/`) and
  `DIR/dictionaries_report.txt`.

  Scripture references in the text are numbered in the packs' English
  numbering with the base core pack's `verses.reference` (`--core PATH`,
  else downloaded as `mix bezalel.data.scrolls` does); the core lexicon's
  keys are also used to count the Strong's numbers `word_study` can reach.
  """

  use Mix.Task

  alias Bezalel.Data.{Dictionaries, DictionariesPack, Download, Net, Pack}

  @switches [core: :string, out: :string]
  @base Path.expand("../../../base.json", __DIR__)
  @examples 20

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    {:ok, _apps} = Application.ensure_all_started(:req)

    pin = Download.pin!("ubs_dictionaries")
    files = fetch(pin)

    digest =
      files
      |> Enum.map(fn {path, bytes} -> {path, Net.sha256(bytes)} end)
      |> Enum.sort()
      |> Net.digest()

    for dictionary <- Dictionaries.dictionaries() do
      case Dictionaries.check_licence(Map.fetch!(files, dictionary.readme), dictionary) do
        :ok -> :ok
        {:error, reason} -> Mix.raise(reason)
      end
    end

    core = Download.base_core!(opts[:core])

    english =
      core
      |> Pack.read("SELECT reference FROM verses")
      |> List.flatten()
      |> Dictionaries.english_numbering()

    lexicon = core |> Pack.read("SELECT strongs FROM lexicon") |> List.flatten() |> MapSet.new()
    {licence, licence_url} = Dictionaries.licence()

    loaded =
      for dictionary <- Dictionaries.dictionaries() do
        Mix.shell().info("Reading #{dictionary.entries}…")
        domains = Dictionaries.domains(Map.fetch!(files, dictionary.domains))

        data =
          Dictionaries.load(Map.fetch!(files, dictionary.entries), domains, dictionary, english)

        row = %{
          key: dictionary.key,
          title: dictionary.title,
          edition: dictionary.edition,
          language: dictionary.language,
          source_url: file_url(pin, dictionary.entries),
          source_sha256: pin["files"][dictionary.entries],
          licence: licence,
          licence_url: licence_url,
          attribution: dictionary.attribution
        }

        {dictionary, row, data}
      end

    rows =
      Map.new(DictionariesPack.columns(), fn {table, _columns} ->
        {table, table_rows(table, loaded)}
      end)

    out = Keyword.get(opts, :out, "out")
    path = Path.join(out, "dictionaries.sqlite")

    DictionariesPack.write(path, rows, %{
      "built_by" => "bezalel_core data/: mix bezalel.data.dictionaries",
      "licences" =>
        Enum.map_join(
          Dictionaries.dictionaries(),
          "; ",
          &"#{&1.title}: #{licence}, #{licence_url} (#{&1.attribution})"
        ),
      "ubs_source" => "#{pin["repo"]}/tree/#{pin["commit"]}/dictionaries",
      "ubs_sha256" => digest,
      "versification" => "Hebrew to English numbering from the base core pack's verses.reference",
      "core_sha256" => base_core()["raw_sha256"],
      "build_sha256" => Dictionaries.build_digest()
    })

    bytes = File.read!(path)
    report = report(pin, digest, loaded, lexicon, path, byte_size(bytes))
    File.write!(Path.join(out, "dictionaries_report.txt"), report)

    Mix.shell().info(
      "Wrote #{path}: #{byte_size(bytes)} bytes, sha256 #{Net.sha256(bytes)}\n" <>
        "Report: #{Path.join(out, "dictionaries_report.txt")}"
    )
  end

  defp table_rows("dictionaries", loaded), do: Enum.map(loaded, &elem(&1, 1))
  defp table_rows("dictionary_entries", loaded), do: Enum.flat_map(loaded, &elem(&1, 2).entries)
  defp table_rows("dictionary_strongs", loaded), do: Enum.flat_map(loaded, &elem(&1, 2).strongs)
  defp table_rows("dictionary_meanings", loaded), do: Enum.flat_map(loaded, &elem(&1, 2).meanings)
  defp table_rows("dictionary_domains", loaded), do: Enum.flat_map(loaded, &elem(&1, 2).domains)

  defp table_rows("dictionary_meaning_domains", loaded),
    do: Enum.flat_map(loaded, &elem(&1, 2).meaning_domains)

  defp file_url(pin, path), do: "#{pin["repo"]}/blob/#{pin["commit"]}/#{path}"

  defp base_core, do: @base |> File.read!() |> Jason.decode!() |> get_in(["packs", "core"])

  defp report(pin, digest, loaded, lexicon, path, size) do
    sections =
      for {dictionary, row, data} <- loaded do
        s = data.stats
        keys = data.strongs |> Enum.map(& &1.strongs) |> Enum.uniq()
        outside = Enum.reject(keys, &MapSet.member?(lexicon, &1))

        [
          "",
          "## #{dictionary.title} (#{dictionary.edition})",
          "",
          "Source: #{row.source_url} (sha256 #{row.source_sha256})",
          "Licence: #{row.licence} (#{row.attribution})",
          "Entries: #{length(data.entries)}; meanings: #{length(data.meanings)}; " <>
            "meaning domains: #{length(data.meaning_domains)}; domain names: #{length(data.domains)}",
          "Strong's codes given, by prefix: #{inspect(Enum.sort(s.prefixes))}; " <>
            "core lexicon keys: #{length(keys)}, of which #{length(outside)} aren't in the core " <>
            "lexicon (word_study can't reach them)#{examples(outside)}",
          "Entries without a Strong's code (unreachable by Strong's): #{length(s.no_strongs)}" <>
            examples(s.no_strongs),
          "References the source lists (counted, not imported): #{s.references}",
          "Senses marked AIGenerated (not imported): #{s.ai_generated}; meanings with no " <>
            "English sense: #{s.no_sense}",
          "Markup rendered, by rule: #{inspect(Enum.sort(s.markup))}",
          "Domains left out (the entry's name differs from the domain file's): " <>
            "#{length(s.dropped_domains)}",
          Enum.map(s.dropped_domains, fn {meaning, code, given, file} ->
            "  #{meaning}: #{code} named #{inspect(given)}, the domain file says #{inspect(file)}\n"
          end),
          "Domain sources left out (named differently): #{length(s.dropped_sources)}",
          Enum.map(s.dropped_sources, fn {meaning, code, given, file} ->
            "  #{meaning}: source #{code} named #{inspect(given)}, the domain file says " <>
              "#{inspect(file)}\n"
          end)
        ]
      end

    [
      "UBS dictionaries import report",
      "",
      "Source: #{pin["repo"]} at #{pin["commit"]} (#{map_size(pin["files"])} files, digest #{digest})",
      "Pack: #{path}, #{size} bytes",
      sections
    ]
    |> List.flatten()
    |> Enum.map_join(fn line ->
      if String.ends_with?(line, "\n"), do: line, else: line <> "\n"
    end)
  end

  defp examples([]), do: ""

  defp examples(list) do
    shown = Enum.take(list, @examples)
    more = if length(list) > @examples, do: ", …", else: ""
    " (" <> Enum.join(shown, ", ") <> more <> ")"
  end

  defp fetch(pin) do
    results =
      for {path, sha256} <- pin["files"] do
        {path,
         Download.fetch(pin["url"] <> path, Path.join(["work", "ubs", path]), &check(&1, sha256))}
      end

    case for {path, {:error, message}} <- results, do: "#{path}: #{message}" do
      [] -> Map.new(results, fn {path, {:ok, bytes}} -> {path, bytes} end)
      errors -> Mix.raise("UBS files differ from pins.json:\n" <> Enum.join(errors, "\n"))
    end
  end

  defp check(bytes, expected) do
    case Net.sha256(bytes) do
      ^expected -> :ok
      actual -> {:error, "sha256 #{actual}, pinned #{inspect(expected)}"}
    end
  end
end
