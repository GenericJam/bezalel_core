defmodule Mix.Tasks.Bezalel.Data.Fathers do
  @shortdoc "Builds out/fathers.sqlite from the Apostolic Fathers' Greek and CAFE's English"

  @moduledoc """
  Builds the `fathers` pack: the Apostolic Fathers registered in core's
  `Bezalel.Study.Ancient.Fathers`, Lake's Greek (and Latin) as corrected by
  Tauber and Macdonald with CAFE's machine-translated English, one passage
  per verse.

      mix bezalel.data.fathers [--out DIR]

  Fetches the files `pins.json` → `fathers` names into `work/fathers/`,
  checking each against its sha256, and writes `DIR/fathers.sqlite`
  (default `out/`) and `DIR/fathers_report.txt`.
  """

  use Mix.Task

  alias Bezalel.Data.{Download, Fathers, FathersPack, Net}

  @switches [out: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    {:ok, _apps} = Application.ensure_all_started(:req)

    pin = Download.pin!("fathers")
    greek = fetch(pin["greek"], "greek")
    english = fetch(pin["english"], "english")

    files =
      Map.new(Fathers.stems(), fn stem ->
        {stem,
         {Map.fetch!(greek, Fathers.greek_file(stem)),
          Map.fetch!(english, Fathers.english_file(stem))}}
      end)

    provenance = Fathers.provenance(pin)
    {rows, counts} = Fathers.passages(files, provenance)

    out = Keyword.get(opts, :out, "out")
    path = Path.join(out, "fathers.sqlite")

    FathersPack.write(path, rows, %{
      "built_by" => "bezalel_core data/: mix bezalel.data.fathers",
      "licences" =>
        "Greek and Latin: Open Apostolic Fathers 1.0 (James Tauber, Seumas Macdonald; Lake's " <>
          "text corrected), doi:10.5281/zenodo.2555673, CC BY-SA 4.0, " <>
          "https://creativecommons.org/licenses/by-sa/4.0/; English: CAFE (James Cuénod), a " <>
          "machine translation (GPT-4o drafts), CC BY-SA 4.0, " <>
          "https://creativecommons.org/licenses/by-sa/4.0/",
      "build_sha256" => Fathers.build_digest(),
      "fathers_sha256" => Fathers.digest(pin),
      "greek_source" => provenance.greek_source,
      "english_source" => provenance.english_source
    })

    source =
      "Sources: #{provenance.greek_source} and #{provenance.english_source} " <>
        "(#{map_size(greek) + map_size(english)} files, digest #{Fathers.digest(pin)})"

    File.write!(
      Path.join(out, "fathers_report.txt"),
      Fathers.report(%{source: source, rows: rows, counts: counts})
    )

    bytes = File.read!(path)

    Mix.shell().info(
      "Wrote #{path}: #{length(rows)} passages, #{byte_size(bytes)} bytes, " <>
        "sha256 #{Net.sha256(bytes)}\nReport: #{Path.join(out, "fathers_report.txt")}"
    )
  end

  defp fetch(side, dir) do
    results =
      for {name, sha256} <- side["files"] do
        {name,
         Download.fetch(
           side["url"] <> name,
           Path.join(["work", "fathers", dir, name]),
           &check(&1, sha256)
         )}
      end

    case for {name, {:error, message}} <- results, do: "#{name}: #{message}" do
      [] ->
        Map.new(results, fn {name, {:ok, bytes}} -> {name, bytes} end)

      errors ->
        Mix.raise("Apostolic Fathers files differ from pins.json:\n" <> Enum.join(errors, "\n"))
    end
  end

  defp check(bytes, expected) do
    case Net.sha256(bytes) do
      ^expected -> :ok
      actual -> {:error, "sha256 #{actual}, pinned #{inspect(expected)}"}
    end
  end
end
