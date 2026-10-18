defmodule Mix.Tasks.Bezalel.Data.Net do
  @shortdoc "Builds out/translations.sqlite with the NET Bible"

  @moduledoc """
  Builds the `translations` pack with the NET Bible's verse text.

      mix bezalel.data.net [--core PATH] [--out DIR]

  Fetches each book from the NET Bible API (labs.bible.org) into
  `work/net/`, checks every response against its sha256 in `pins.json` →
  `net.books`, and writes `DIR/translations.sqlite` (default `out/`) and
  `DIR/net_report.txt`. The report compares NET's references with the BSB
  references of a core pack: `--core PATH`, else the phone app's
  `../../bezalel/data/out/core.sqlite` if it is there.

  When the publisher revises the text, the check fails, names the books
  and keeps the new responses as `work/net/<file>.unverified`; review them
  (build from them by moving them over the cached files) before changing
  the pins.
  """

  use Mix.Task

  alias Bezalel.Data.{Books, Download, Net, Pack, Report}

  @switches [core: :string, out: :string]
  @phone_core "../../bezalel/data/out/core.sqlite"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    {:ok, _apps} = Application.ensure_all_started(:req)

    pin = Download.pin!("net")
    responses = fetch(pin)

    digest =
      responses |> Enum.map(fn {code, bytes} -> {code, Net.sha256(bytes)} end) |> Net.digest()

    parsed =
      responses |> Map.new(fn {code, bytes} -> {code, Jason.decode!(bytes)} end) |> Net.rows()

    out = Keyword.get(opts, :out, "out")
    path = Path.join(out, "translations.sqlite")
    translation = Map.merge(Net.translation(), %{source_url: pin["api"], source_sha256: digest})

    Pack.write(path, [translation], %{"net" => parsed.rows}, %{
      "built_by" => "bezalel_core data/: mix bezalel.data.net",
      "licences" =>
        "NET Bible: free non-commercial use by permission (netbible.com/copyright); " <>
          "the acknowledgement is translations.copyright",
      "net_source" => pin["api"],
      "net_sha256" => digest
    })

    report =
      Report.net(%{
        rows: parsed.rows,
        empty: parsed.empty,
        headings: parsed.headings,
        source:
          "Source: #{pin["api"]}, one request per book (formatting=full); " <>
            "digest of the 66 responses #{digest}",
        bsb: bsb_references(opts[:core])
      })

    File.write!(Path.join(out, "net_report.txt"), report)
    bytes = File.read!(path)

    Mix.shell().info(
      "Wrote #{path}: #{length(parsed.rows)} rows, #{byte_size(bytes)} bytes, " <>
        "sha256 #{Net.sha256(bytes)}\nReport: #{Path.join(out, "net_report.txt")}"
    )
  end

  defp fetch(pin) do
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

  defp check(bytes, expected) do
    case Net.sha256(bytes) do
      ^expected -> :ok
      actual -> {:error, "sha256 #{actual}, pinned #{inspect(expected)}"}
    end
  end

  defp bsb_references(core) do
    path = core || if File.regular?(@phone_core), do: @phone_core

    if path do
      references = path |> Pack.read("SELECT reference FROM bsb_verses") |> List.flatten()
      {"#{Path.expand(path)} (bsb_verses)", references}
    end
  end
end
