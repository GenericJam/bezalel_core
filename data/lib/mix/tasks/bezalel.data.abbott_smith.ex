defmodule Mix.Tasks.Bezalel.Data.AbbottSmith do
  @shortdoc "Writes ../priv/study/abbott_smith_pages.json from the Abbott-Smith TEI"

  @moduledoc """
  Writes core's `priv/study/abbott_smith_pages.json`: the printed page each
  Abbott-Smith entry starts on and its page in the Internet Archive scan
  (`Bezalel.Data.AbbottSmith`), for the lexicon citations' links.

      mix bezalel.data.abbott_smith [--out PATH]

  Fetches `pins.json` → `abbott_smith`'s TEI and page numbers into
  `work/abbott_smith/`, checking each against its sha256.
  """

  use Mix.Task

  alias Bezalel.Data.{AbbottSmith, Download, Net}

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [out: :string])
    {:ok, _apps} = Application.ensure_all_started(:req)
    pin = Download.pin!("abbott_smith")

    tei = fetch!(pin["tei"], "abbott-smith.tei.xml", pin["tei_sha256"])
    numbers = fetch!(pin["page_numbers"], "page_numbers.json", pin["page_numbers_sha256"])
    {pages, tokens} = AbbottSmith.pages(tei, Jason.decode!(numbers))

    header = %{
      "what" =>
        "The printed page each Abbott-Smith entry starts on, by Strong's number; scan_tokens: the Internet Archive scan's page for a page it didn't number.",
      "source" => "#{pin["repo"]} @ #{pin["commit"]}; #{pin["scan"]}",
      "built_by" => "bezalel_core data/: mix bezalel.data.abbott_smith"
    }

    # The core checkout's source priv (a path dependency), not its build copy.
    default =
      Path.join(Mix.Project.deps_paths()[:bezalel_core], "priv/study/abbott_smith_pages.json")

    path = Keyword.get(opts, :out, default)
    File.write!(path, render(header, pages, tokens))
    Mix.shell().info("Wrote #{path}: #{map_size(pages)} entries")
  end

  # One entry per line, Strong's numbers in order then lemmas, so a rebuild
  # diffs line by line.
  defp render(header, pages, tokens) do
    fields =
      Enum.map_join(Enum.sort(header), ",\n", fn {k, v} ->
        "  #{Jason.encode!(k)}: #{Jason.encode!(v)}"
      end)

    entries = pages |> Enum.sort_by(fn {key, _} -> order(key) end) |> object("    ")

    scan = tokens |> Enum.sort_by(fn {page, _} -> String.to_integer(page) end) |> object("    ")
    "{\n#{fields},\n  \"pages\": {\n#{entries}\n  },\n  \"scan_tokens\": {\n#{scan}\n  }\n}\n"
  end

  defp order("G" <> n), do: {0, String.to_integer(n), ""}
  defp order(key), do: {1, 0, key}

  defp object(pairs, indent),
    do:
      Enum.map_join(pairs, ",\n", fn {k, v} ->
        "#{indent}#{Jason.encode!(k)}: #{Jason.encode!(v)}"
      end)

  defp fetch!(url, name, sha256) do
    check = fn bytes ->
      if Net.sha256(bytes) == sha256, do: :ok, else: {:error, "sha256 mismatch"}
    end

    case Download.fetch(url, Path.join("work/abbott_smith", name), check) do
      {:ok, bytes} -> bytes
      {:error, message} -> Mix.raise(message)
    end
  end
end
