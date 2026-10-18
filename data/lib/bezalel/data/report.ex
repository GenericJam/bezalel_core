defmodule Bezalel.Data.Report do
  @moduledoc """
  The import reports. NET (`out/net_report.txt`): what was dropped, and how
  NET's verse set compares with the BSB references of a core pack
  (`bsb_verses.reference`), so the study tools know where a NET lookup can
  come back empty. Scrolls (`out/scrolls_report.txt`): what the scrolls pack
  holds and what it leaves out, by rule.
  """

  alias Bezalel.Data.Books
  alias Bezalel.Study.Ancient.Scrolls, as: Registry

  @examples 25
  # The ETCBC scrolls studybible-mcp imported into the ancient pack.
  @ancient_pack ~w(CD 1QS 1QSa 1QpHab)

  @doc """
  The report text. `info` has `:rows`, `:empty` (references the source
  gives without text), `:headings` (`{reference, class, text}` dropped),
  `:source` (lines naming the source) and `:bsb`, either
  `{label, [reference]}` or nil when no core pack was available.
  """
  @spec net(map()) :: String.t()
  def net(info) do
    net_refs = Enum.map(info.rows, & &1.reference)

    [
      "NET Bible import report",
      "",
      info.source,
      "Rows: #{length(net_refs)} (#{count_verse0(net_refs)} Psalm superscriptions as verse 0)",
      "Rows with LORD (small capitals in the source): " <>
        "#{Enum.count(info.rows, &String.contains?(&1.text, "LORD"))}",
      "",
      "Verses the source gives without text: #{length(info.empty)}",
      examples(info.empty),
      "",
      "Headings dropped: #{length(info.headings)}",
      info.headings
      |> Enum.group_by(&elem(&1, 1))
      |> Enum.sort()
      |> Enum.map(fn {class, headings} ->
        [
          "  #{class}: #{length(headings)}",
          headings
          |> Enum.take(5)
          |> Enum.map(fn {reference, _class, text} -> "    #{reference}: #{text}" end)
        ]
      end),
      "",
      comparison(net_refs, info.bsb)
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Compares two reference lists: `%{both: n, only_a: [ref], only_b: [ref]}`,
  the lists in canonical order.
  """
  @spec compare([String.t()], [String.t()]) :: %{
          both: non_neg_integer(),
          only_a: [String.t()],
          only_b: [String.t()]
        }
  def compare(a, b) do
    set_a = MapSet.new(a)
    set_b = MapSet.new(b)

    %{
      both: set_a |> MapSet.intersection(set_b) |> MapSet.size(),
      only_a: set_a |> MapSet.difference(set_b) |> sort(),
      only_b: set_b |> MapSet.difference(set_a) |> sort()
    }
  end

  @doc """
  The scrolls report text. `info`: `:source` (a line), `:data`
  (`Bezalel.Data.Scrolls.load/1`), `:works` (the registry works imported),
  `:passages` and `:anomalies` (`Scrolls.passages/3`) and `:biblical`
  (`Scrolls.biblical/3`).
  """
  @spec scrolls(map()) :: String.t()
  def scrolls(info) do
    [
      "Scrolls pack import report",
      "",
      info.source,
      "",
      works_section(info),
      "",
      biblical_section(info.biblical),
      "",
      dropped_section(info)
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp works_section(info) do
    by_work = Enum.group_by(info.passages, & &1.work_key)
    compositions = Registry.compositions()

    [
      "Non-biblical works: #{length(compositions)} compositions, #{length(info.works)} manuscripts, " <>
        "#{length(info.passages)} passages (one per fragment or column label)",
      Enum.map(compositions, fn composition ->
        works = Enum.filter(info.works, &(&1.composition == composition.title))

        [
          "  #{composition.title}:",
          Enum.map(works, fn work ->
            rows = Map.get(by_work, work.key, [])
            lines = rows |> Enum.map(&length(String.split(&1.original_text, "\n"))) |> Enum.sum()
            languages = rows |> Enum.frequencies_by(& &1.original_language) |> Enum.sort()

            name = if work.name, do: " (#{work.name})", else: ""

            "    #{work.reference_title}#{name}: " <>
              "#{length(rows)} passages, #{lines} lines, " <>
              Enum.map_join(languages, ", ", fn {language, n} -> "#{language} #{n}" end)
          end)
        ]
      end),
      "Line-number anomalies (kept as ETCBC numbers them): #{length(info.anomalies)}",
      Enum.map(info.anomalies, fn {siglum, label, problem} ->
        "  #{siglum} #{label}: #{problem}"
      end)
    ]
  end

  defp biblical_section(biblical) do
    verses = biblical.verses
    references = verses |> Enum.map(& &1.reference) |> Enum.uniq()
    with_verses = Enum.count(biblical.manuscripts, &(&1.verses > 0))

    only_reconstructed =
      verses
      |> Enum.group_by(& &1.reference)
      |> Enum.filter(fn {_ref, rows} -> Enum.all?(rows, &(&1.preserved_letters == 0)) end)
      |> Enum.map(&elem(&1, 0))

    books = verses |> Enum.map(& &1.book) |> Enum.uniq() |> Enum.sort_by(&Books.index/1)
    missing_books = Enum.map(Books.all(), &elem(&1, 0)) |> Enum.take(39) |> Kernel.--(books)

    [
      "Biblical manuscripts: #{length(biblical.manuscripts)} (ETCBC scroll nodes marked biblical, by siglum); " <>
        "#{with_verses} with at least one identified verse",
      "  by site: " <>
        (biblical.manuscripts
         |> Enum.frequencies_by(&site_group/1)
         |> Enum.sort()
         |> Enum.map_join(", ", fn {site, n} -> "#{site} #{n}" end)),
      "  with a conventional name (dss_names.json): #{Enum.count(biblical.manuscripts, & &1.name)}",
      "Verse readings (manuscript × verse): #{length(verses)}",
      "Distinct verses covered: #{length(references)}",
      "Books covered: #{length(books)} (#{Enum.join(books, " ")})",
      "Books with no reading: #{Enum.join(missing_books, " ")}",
      "Readings wholly reconstructed (every letter in [ ]): " <>
        "#{Enum.count(verses, &(&1.preserved_letters == 0))}",
      "Verses whose every reading is wholly reconstructed: #{length(only_reconstructed)}",
      examples(sort(only_reconstructed)),
      "Verses read in a manuscript twice, apart (occurrence 2+): " <>
        "#{Enum.count(verses, &(&1.occurrence > 1))}",
      "Readings in Aramaic: #{Enum.count(verses, &(&1.language == "Aramaic"))}"
    ]
  end

  defp counts(frequencies),
    do: frequencies |> Enum.sort() |> Enum.map_join(", ", fn {type, n} -> "#{type} #{n}" end)

  defp site_group(%{site: "Qumran Cave " <> _}), do: "Qumran caves"
  defp site_group(%{site: site}), do: site

  defp dropped_section(info) do
    biblical = info.biblical
    imported = MapSet.new(info.works, & &1.siglum)

    {in_ancient, skipped} =
      info.data.scrolls.nodes
      |> Enum.reject(&(&1.biblical or MapSet.member?(imported, &1.siglum)))
      |> Enum.map(& &1.siglum)
      |> Enum.split_with(&(&1 in @ancient_pack))

    biblical_sigla =
      info.data.scrolls.nodes |> Enum.filter(& &1.biblical) |> MapSet.new(& &1.siglum)

    split = Enum.filter(skipped, &MapSet.member?(biblical_sigla, &1))
    unidentified_words = biblical.unidentified |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    [
      "Left out, by rule:",
      "  In the ancient pack already (studybible-mcp's import, not repeated here): " <>
        Enum.join(in_ancient, " "),
      "  Non-biblical scroll nodes not registered as works (the long tail of small " <>
        "fragments, and works not judged major): #{length(skipped)}",
      "    " <> Enum.join(Enum.take(skipped, 40), " ") <> " …",
      "    of which the non-biblical part of a manuscript whose biblical part is imported: " <>
        Enum.join(split, " "),
      "  Words whose ETCBC book is not a book of the Hebrew Bible (unidentified fragments; " <>
        "ETCBC gives the scroll or photograph siglum): #{unidentified_words} words in " <>
        "#{length(biblical.unidentified)} values",
      "    " <> Enum.map_join(biblical.unidentified, " ", fn {book, n} -> "#{book}:#{n}" end),
      "  Signs of biblical lines in no word with a book, outside every verse on their line " <>
        "(no verse; left out; the letters are 2Q29's unplaced fragments): " <>
        counts(biblical.wordless_signs.dropped),
      "  Kept: signs in no word inside one verse's words on a line (in its text, where the " <>
        "scroll has them): " <> counts(biblical.wordless_signs.kept),
      "  ETCBC's morpheme break (׳), analytical not written: dropped from every text",
      "Kept with ETCBC's own numbering (no such verse in the core pack's English numbering): " <>
        "#{length(biblical.unmapped)}",
      examples(Enum.uniq(biblical.unmapped))
    ]
  end

  @doc "References in canonical order (book, chapter, verse)."
  @spec sort(Enumerable.t()) :: [String.t()]
  def sort(references) do
    Enum.sort_by(references, fn reference ->
      [book, chapter, verse] = String.split(reference, ".")
      {Books.index(book), String.to_integer(chapter), String.to_integer(verse)}
    end)
  end

  defp comparison(_net_refs, nil) do
    "No core pack to compare with (pass --core PATH to a core.sqlite with bsb_verses)."
  end

  defp comparison(net_refs, {label, bsb_refs}) do
    %{both: both, only_a: only_net, only_b: only_bsb} = compare(net_refs, bsb_refs)

    [
      "Compared with #{label}: #{length(bsb_refs)} BSB references " <>
        "(#{count_verse0(bsb_refs)} superscriptions)",
      "In both: #{both}",
      section("Only in NET", only_net),
      section("Only in the BSB (a NET lookup finds nothing)", only_bsb)
    ]
  end

  defp section(title, references) do
    {verse0, verses} = Enum.split_with(references, &String.ends_with?(&1, ".0"))

    [
      "#{title}: #{length(references)} (#{length(verse0)} superscriptions)",
      examples(verses),
      examples(verse0)
    ]
  end

  defp examples([]), do: []

  defp examples(references) do
    shown = Enum.take(references, @examples)
    more = length(references) - length(shown)
    "  " <> Enum.join(shown, " ") <> if(more > 0, do: " … and #{more} more", else: "")
  end

  defp count_verse0(references), do: Enum.count(references, &String.ends_with?(&1, ".0"))
end
