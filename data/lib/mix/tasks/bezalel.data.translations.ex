defmodule Mix.Tasks.Bezalel.Data.Translations do
  @shortdoc "Builds out/translations.sqlite: the NET, JPS 1917, ULT and UST"

  @moduledoc """
  Builds the `translations` pack: the NET Bible, the JPS 1917 and the
  Literal and Simplified Texts adapted from unfoldingWord's ULT and UST.

      mix bezalel.data.translations [--core PATH] [--out DIR]

  Downloads into `work/` and checks each download against its sha256 in
  `pins.json`:

    * `net`: each book from the NET Bible API (labs.bible.org) into
      `work/net/`;
    * `jps`: eBible.org's `engjps_usfm.zip` into `work/jps/`;
    * `ult`, `ust`: every book file, LICENSE.md and manifest.yaml of the
      pinned Door43 commit into `work/ult/`, `work/ust/`.

  The JPS's inline Hebrew verse numbers are mapped with the base core
  pack's `verses.reference` (`Bezalel.Data.Download.base_core!/1`: `--core
  PATH`, else downloaded from `base.json`'s URL into `work/base/`; either
  way checked against `base.json`), whose `bsb_verses` references the
  reports compare each translation's verse set with.

  Writes `DIR/translations.sqlite` (default `out/`), `DIR/net_report.txt`
  and `DIR/translations_report.txt` (the JPS, ULT and UST).

  When a source changes, the check fails, names the files and keeps the new
  bytes as `<file>.unverified`; review them (build from them by moving them
  over the cached files) before changing the pins.
  """

  use Mix.Task

  alias Bezalel.Data.{Books, Door43, Download, Jps, Net, Pack, Report, Scrolls}

  @switches [core: :string, out: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    {:ok, _apps} = Application.ensure_all_started(:req)

    core = Download.base_core!(opts[:core])
    references = core |> Pack.read("SELECT reference FROM verses") |> List.flatten()
    bsb = {"the base core pack (bsb_verses)", bsb_references(core)}

    net_pin = Download.pin!("net")
    responses = fetch_net(net_pin)

    net_digest =
      responses |> Enum.map(fn {code, bytes} -> {code, Net.sha256(bytes)} end) |> Net.digest()

    net =
      responses |> Map.new(fn {code, bytes} -> {code, Jason.decode!(bytes)} end) |> Net.rows()

    jps_pin = Download.pin!("jps")
    zip = fetch!(jps_pin["url"], Path.join(["work", "jps", "engjps_usfm.zip"]), jps_pin["sha256"])
    jps = Jps.rows(Jps.files(zip), Scrolls.english_numbering(references))

    door43 =
      Map.new(Door43.keys(), fn key ->
        pin = Download.pin!(key)
        files = fetch_files(key, pin)
        Door43.check_licence!(key, files["LICENSE.md"])
        {key, %{pin: pin, digest: Door43.digest(pin["files"]), parsed: Door43.rows(files)}}
      end)

    sources = %{
      "net" => {net_pin["api"], net_digest},
      "jps1917" => {jps_pin["url"], jps_pin["sha256"]},
      "ult" => {Door43.source(door43["ult"].pin), door43["ult"].digest},
      "ust" => {Door43.source(door43["ust"].pin), door43["ust"].digest}
    }

    translations =
      for translation <- [
            Net.translation(),
            Jps.translation() | Enum.map(Door43.keys(), &Door43.translation/1)
          ] do
        {url, sha256} = sources[translation.key]
        Map.merge(translation, %{source_url: url, source_sha256: sha256})
      end

    out = Keyword.get(opts, :out, "out")
    path = Path.join(out, "translations.sqlite")

    Pack.write(
      path,
      translations,
      %{
        "net" => net.rows,
        "jps1917" => jps.rows,
        "ult" => door43["ult"].parsed.rows,
        "ust" => door43["ust"].parsed.rows
      },
      %{
        "built_by" => "bezalel_core data/: mix bezalel.data.translations",
        "licences" =>
          "NET Bible: free non-commercial use by permission (netbible.com/copyright); " <>
            "the acknowledgement is translations.copyright. JPS 1917: public domain. " <>
            "ult, ust (adapted from unfoldingWord's ULT and UST): CC BY-SA 4.0, " <>
            "https://creativecommons.org/licenses/by-sa/4.0/; attribution and changes in " <>
            "translations.copyright. Each translation's licence is its translations.licence.",
        "net_source" => net_pin["api"],
        "net_sha256" => net_digest,
        "jps_source" => jps_pin["url"],
        "jps_sha256" => jps_pin["sha256"],
        "ult_source" => Door43.source(door43["ult"].pin),
        "ult_sha256" => door43["ult"].digest,
        "ust_source" => Door43.source(door43["ust"].pin),
        "ust_sha256" => door43["ust"].digest,
        "versification" =>
          "English (the packs'); the JPS's inline Hebrew numbers mapped with the base core " <>
            "pack's verses.reference",
        "core_sha256" => base_core_sha256()
      }
    )

    File.write!(
      Path.join(out, "net_report.txt"),
      Report.net(%{
        rows: net.rows,
        empty: net.empty,
        headings: net.headings,
        source:
          "Source: #{net_pin["api"]}, one request per book (formatting=full); " <>
            "digest of the 66 responses #{net_digest}",
        bsb: bsb
      })
    )

    File.write!(
      Path.join(out, "translations_report.txt"),
      Enum.map_join(
        [
          {"JPS 1917 import report", "Source: #{jps_pin["url"]}, sha256 #{jps_pin["sha256"]}",
           jps},
          ult_ust_report("ult", door43["ult"]),
          ult_ust_report("ust", door43["ust"])
        ],
        "\n\n",
        fn {title, source, parsed} ->
          Report.translation(%{title: title, source: source, parsed: parsed, bsb: bsb})
        end
      )
    )

    bytes = File.read!(path)

    counts =
      Enum.map_join(
        Pack.read(
          path,
          "SELECT translation, COUNT(*) FROM translation_verses GROUP BY translation"
        ),
        ", ",
        fn [key, n] -> "#{key} #{n}" end
      )

    Mix.shell().info(
      "Wrote #{path}: #{counts} rows, #{byte_size(bytes)} bytes, sha256 #{Net.sha256(bytes)}\n" <>
        "Reports: #{Path.join(out, "net_report.txt")}, #{Path.join(out, "translations_report.txt")}"
    )
  end

  defp ult_ust_report(key, %{pin: pin, digest: digest, parsed: parsed}) do
    {"#{Door43.translation(key).name} import report",
     "Source: #{Door43.source(pin)} (tag #{pin["tag"]}), #{map_size(pin["files"])} files, " <>
       "digest #{digest}", parsed}
  end

  @base Path.expand("../../../base.json", __DIR__)

  defp base_core_sha256,
    do: @base |> File.read!() |> Jason.decode!() |> get_in(["packs", "core", "raw_sha256"])

  defp fetch_net(pin) do
    results =
      Books.all()
      |> Enum.with_index(1)
      |> Enum.map(fn {{code, _name, _chapters} = book, number} ->
        file =
          Path.join(["work", "net", "#{String.pad_leading("#{number}", 2, "0")}-#{code}.json"])

        {code, Download.fetch(Net.url(book), file, &check(&1, get_in(pin, ["books", code])))}
      end)

    case for {code, {:error, message}} <- results, do: "#{code}: #{message}" do
      [] -> Enum.map(results, fn {code, {:ok, bytes}} -> {code, bytes} end)
      errors -> Mix.raise("NET responses differ from pins.json:\n" <> Enum.join(errors, "\n"))
    end
  end

  defp fetch_files(key, pin) do
    results =
      for {name, sha256} <- pin["files"] do
        {name,
         Download.fetch(pin["url"] <> name, Path.join(["work", key, name]), &check(&1, sha256))}
      end

    case for {name, {:error, message}} <- results, do: "#{name}: #{message}" do
      [] -> Map.new(results, fn {name, {:ok, bytes}} -> {name, bytes} end)
      errors -> Mix.raise("#{key} files differ from pins.json:\n" <> Enum.join(errors, "\n"))
    end
  end

  defp fetch!(url, path, sha256) do
    case Download.fetch(url, path, &check(&1, sha256)) do
      {:ok, bytes} -> bytes
      {:error, message} -> Mix.raise("#{url} differs from pins.json: #{message}")
    end
  end

  defp check(bytes, expected) do
    case Net.sha256(bytes) do
      ^expected -> :ok
      actual -> {:error, "sha256 #{actual}, pinned #{inspect(expected)}"}
    end
  end

  defp bsb_references(core),
    do: core |> Pack.read("SELECT reference FROM bsb_verses") |> List.flatten()
end
