defmodule Mix.Tasks.Bezalel.Data.Scrolls do
  @shortdoc "Builds out/scrolls.sqlite from ETCBC/dss"

  @moduledoc """
  Builds the `scrolls` pack: the major non-biblical Dead Sea Scrolls works
  registered in core's `Bezalel.Study.Ancient.Scrolls` and every biblical
  manuscript's verse readings, from the ETCBC/dss Text-Fabric release.

      mix bezalel.data.scrolls [--core PATH] [--out DIR]

  Fetches the feature files `pins.json` → `dss` names into `work/dss/`,
  checking each against its sha256, and writes `DIR/scrolls.sqlite`
  (default `out/`) and `DIR/scrolls_report.txt`.

  The verse numbers are mapped from ETCBC's Hebrew numbering to the core
  pack's English one with the base core pack's `verses.reference`: `--core
  PATH` (e.g. the phone app's `data/out/core.sqlite`), else it is downloaded
  from `base.json`'s URL into `work/base/`. Either way its sha256 must be
  `base.json`'s.
  """

  use Mix.Task

  alias Bezalel.Data.{Download, Net, Pack, Report, Scrolls, ScrollsPack}
  alias Bezalel.Study.Ancient

  @switches [core: :string, out: :string]
  @base Path.expand("../../../base.json", __DIR__)
  @names Path.expand("../../../dss_names.json", __DIR__)

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    {:ok, _apps} = Application.ensure_all_started(:req)

    pin = Download.pin!("dss")
    files = fetch(pin)

    digest =
      files
      |> Enum.map(fn {name, bytes} -> {name, Net.sha256(bytes)} end)
      |> Enum.sort()
      |> Net.digest()

    core = core!(opts[:core])

    Mix.shell().info("Reading ETCBC/dss…")
    data = Scrolls.load(&Map.fetch!(files, &1))
    works = Enum.filter(Ancient.corpus("qumran").works, &(Ancient.pack(&1) == :scrolls))
    provenance = Scrolls.provenance(pin)
    {passages, anomalies} = Scrolls.passages(data, works, provenance)

    english =
      core
      |> Pack.read("SELECT reference FROM verses")
      |> List.flatten()
      |> Scrolls.english_numbering()

    names = @names |> File.read!() |> Jason.decode!() |> Map.fetch!("names")
    biblical = Scrolls.biblical(data, english, names)

    out = Keyword.get(opts, :out, "out")
    path = Path.join(out, "scrolls.sqlite")

    ScrollsPack.write(path, passages, biblical.manuscripts, biblical.verses, %{
      "built_by" => "bezalel_core data/: mix bezalel.data.scrolls",
      "licences" =>
        "ETCBC/dss (Abegg, Bowley, Cook): CC BY-NC 4.0, https://creativecommons.org/licenses/by-nc/4.0/; " <>
          "manuscript names: the conventional scholarly designations (facts, e.g. 4QDeutj), " <>
          "as the Leon Levy Dead Sea Scrolls Digital Library (IAA) lists them",
      "build_sha256" => Scrolls.build_digest(),
      "dss_source" => provenance.source_url,
      "dss_sha256" => digest,
      "versification" => "Hebrew to English numbering from the base core pack's verses.reference",
      "core_sha256" => base_core()["raw_sha256"]
    })

    report =
      Report.scrolls(%{
        source:
          "Source: #{provenance.source_url} (#{map_size(files)} feature files, digest #{digest})",
        data: data,
        works: works,
        passages: passages,
        anomalies: anomalies,
        biblical: biblical
      })

    File.write!(Path.join(out, "scrolls_report.txt"), report)
    bytes = File.read!(path)

    Mix.shell().info(
      "Wrote #{path}: #{length(passages)} passages, #{length(biblical.verses)} verse readings, " <>
        "#{byte_size(bytes)} bytes, sha256 #{Net.sha256(bytes)}\n" <>
        "Report: #{Path.join(out, "scrolls_report.txt")}"
    )
  end

  defp fetch(pin) do
    results =
      for {name, sha256} <- pin["files"] do
        {name,
         Download.fetch(pin["url"] <> name, Path.join(["work", "dss", name]), &check(&1, sha256))}
      end

    case for {name, {:error, message}} <- results, do: "#{name}: #{message}" do
      [] -> Map.new(results, fn {name, {:ok, bytes}} -> {name, bytes} end)
      errors -> Mix.raise("ETCBC/dss files differ from pins.json:\n" <> Enum.join(errors, "\n"))
    end
  end

  defp check(bytes, expected) do
    case Net.sha256(bytes) do
      ^expected -> :ok
      actual -> {:error, "sha256 #{actual}, pinned #{inspect(expected)}"}
    end
  end

  defp base_core, do: @base |> File.read!() |> Jason.decode!() |> get_in(["packs", "core"])

  # The base core pack, checked against base.json.
  defp core!(path) do
    pin = base_core()

    path =
      path ||
        (
          zst = Path.join(["work", "base", "core.sqlite.zst"])

          case Download.fetch(pin["url"], zst, &check(&1, pin["sha256"])) do
            {:ok, _} -> :ok
            {:error, message} -> Mix.raise("base core pack: #{message}")
          end

          raw = Path.join(["work", "base", "core.sqlite"])

          unless File.regular?(raw) and Net.sha256(File.read!(raw)) == pin["raw_sha256"] do
            {_, 0} = System.cmd("zstd", ["-d", "-q", "-f", zst, "-o", raw])
          end

          raw
        )

    if Net.sha256(File.read!(path)) != pin["raw_sha256"] do
      Mix.raise("#{path} is not the base core pack (sha256 differs from base.json)")
    end

    path
  end
end
