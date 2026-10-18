defmodule Bezalel.Data.Report do
  @moduledoc """
  The NET import report (`out/net_report.txt`): what was dropped, and how
  NET's verse set compares with the BSB references of a core pack
  (`bsb_verses.reference`), so the study tools know where a NET lookup can
  come back empty.
  """

  alias Bezalel.Data.Books

  @examples 25

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
