defmodule Bezalel.Data.AbbottSmith do
  @moduledoc """
  The printed page each Abbott-Smith entry starts on, for
  `Bezalel.Study.Citations.abbott_smith/2`'s link into the Internet Archive
  scan: from the TEI edition's page breaks (`<pb n="…"/>`) and entries
  (`<entry n="lemma|G26">`), and the scan's detected page numbers (its
  `_page_numbers.json`: leaf → printed page).

  An entry's page is the last page break before it. The scan's viewer finds
  a page by its printed number when the Internet Archive detected it; for
  the few it missed, `scan_tokens` gives `n` and the leaf index the detected
  pages imply (leaf − 1, the viewer's zero-based index).
  """

  @doc """
  `{pages, scan_tokens}`: `%{"G26" => "3"}` for every entry, by Strong's
  number, or as `"AS_<lemma>"` for an entry the TEI gives none (the core
  pack's `lexicon.strongs` for those), and `%{"1" => "n20"}` for each page
  the scan didn't number.
  """
  @spec pages(String.t(), map()) :: {%{String.t() => String.t()}, %{String.t() => String.t()}}
  def pages(tei, page_numbers) do
    {labels, offset} = scan_pages(page_numbers)
    marks = Regex.compile!(~S'<pb n="([^"]+)"|<entry n="([^"|]*)(?:\|(G[0-9]+))?"', "u")

    {_page, pages} =
      marks
      |> Regex.scan(tei, capture: :all_but_first)
      |> Enum.reduce({nil, %{}}, fn
        [page], {_page, acc} ->
          {page, acc}

        ["", lemma], {page, acc} when page != nil ->
          {page, Map.put_new(acc, "AS_" <> lemma, page)}

        ["", _lemma, strongs], {page, acc} when page != nil ->
          {page, Map.put_new(acc, strongs, page)}

        _mark, state ->
          state
      end)

    tokens =
      for page <- pages |> Map.values() |> Enum.uniq(),
          not MapSet.member?(labels, page),
          {number, ""} <- [Integer.parse(page)],
          into: %{},
          do: {page, "n#{number + offset - 1}"}

    {pages, tokens}
  end

  # The labels the scan detected, and the leaf − page offset most of them share.
  defp scan_pages(%{"pages" => pages}) do
    labelled =
      for %{"pageNumber" => n, "leafNum" => leaf} <- pages, n not in [nil, ""], do: {n, leaf}

    offset =
      labelled
      |> Enum.flat_map(fn {n, leaf} ->
        case Integer.parse(n) do
          {number, ""} -> [leaf - number]
          _ -> []
        end
      end)
      |> Enum.frequencies()
      |> Enum.max_by(&elem(&1, 1), fn -> {0, 0} end)
      |> elem(0)

    {MapSet.new(labelled, &elem(&1, 0)), offset}
  end
end
