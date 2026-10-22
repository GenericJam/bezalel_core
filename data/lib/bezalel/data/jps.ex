defmodule Bezalel.Data.Jps do
  @moduledoc """
  The JPS 1917 (*The Holy Scriptures according to the Masoretic Text*, the
  Jewish Publication Society, 1917; public domain) as `translation_verses`
  rows, from eBible.org's USFM (`engjps_usfm.zip`, pinned by sha256: the
  URL isn't versioned).

  eBible numbers the verses in the English way (Malachi 4, Psalm titles in
  verse 1) and writes the Hebrew verse numbers inline where they differ:
  `\\v 1 (3-1) A Psalm of David… (3-2) LORD, how many…`. Each verse's text
  is read by `Bezalel.Data.Usfm`; then the Hebrew numbers are mapped to the
  packs' English numbering with the base core pack's `verses.reference`
  (`Psa.3.0(3.1)`): a Psalm title, the Hebrew verses its first verse holds
  that the core numbers as English verse 0, becomes verse 0 (`Psa.3.0`), as
  the NET's does; every other verse keeps eBible's English number, and the
  inline numbers are removed (`hebrew_numbers/2`).

  The text is otherwise as eBible gives it, including what its USFM carries
  as plain words: the first words of a book in capitals ("IN THE
  beginning") and the Psalter's five book headings at the start of Psalms
  1, 42, 73, 90 and 107 ("BOOK I"), which have no markup to drop them by
  (data/AGENTS.md rule 3: never by matching words).
  """

  alias Bezalel.Data.{Books, Usfm}
  alias Bezalel.Study.Translations

  @doc """
  The JPS's `translations` row (without the source columns): core's
  `Bezalel.Study.Translations` entry, `jps1917`.
  """
  @spec translation() :: map()
  def translation do
    "jps1917"
    |> Translations.get()
    |> Map.take(~w(key name abbreviation url copyright licence)a)
  end

  @doc """
  The book files of the zip (`%{usfm_code => text}`), checking that its
  `copr.htm` says the text is public domain.
  """
  @spec files(binary()) :: %{String.t() => String.t()}
  def files(zip) do
    {:ok, entries} = :zip.unzip(zip, [:memory])
    entries = Map.new(entries, fn {name, bytes} -> {List.to_string(name), bytes} end)

    unless String.contains?(Map.get(entries, "copr.htm", ""), "Public Domain") do
      raise ArgumentError, "engjps: copr.htm doesn't say Public Domain"
    end

    for {name, bytes} <- entries,
        [_, code] <- [Regex.run(Regex.compile!("^[0-9]{2}-([0-9A-Z]{3})engjps\\.usfm$"), name)],
        into: %{},
        do: {code, bytes}
  end

  @doc """
  Every book's rows in canonical order, with what `Bezalel.Data.Usfm`
  dropped and what the Hebrew numbers did (`hebrew_numbers/2`). `english`
  maps `{book, hebrew_chapter, hebrew_verse}` to the English `{chapter,
  verse}` (or nil), `Bezalel.Data.Scrolls.english_numbering/1` of the base
  core pack's references.
  """
  @spec rows(%{String.t() => String.t()}, (tuple() -> {integer(), integer()} | nil)) :: map()
  def rows(files, english) do
    unknown = Map.keys(files) -- Enum.map(Books.all(), &String.upcase(elem(&1, 0)))
    if unknown != [], do: raise(ArgumentError, "engjps: unknown books #{inspect(unknown)}")

    books =
      for {code, _name, _chapters} <- Books.all(),
          usfm = String.upcase(code),
          text = files[usfm] do
        book = Usfm.book(text, usfm, code)
        numbered = hebrew_numbers(book.rows, english)
        Map.merge(book, numbered)
      end

    %{
      books: Enum.map(books, &hd(&1.rows).book),
      rows: Enum.flat_map(books, & &1.rows),
      empty: Enum.flat_map(books, & &1.empty),
      headings: Enum.flat_map(books, & &1.headings),
      footnotes: Enum.flat_map(books, & &1.footnotes),
      bridges: Enum.flat_map(books, & &1.bridges),
      numbers: Enum.sum_by(books, & &1.numbers),
      titles: Enum.flat_map(books, & &1.titles),
      elsewhere: Enum.flat_map(books, & &1.elsewhere)
    }
  end

  @doc """
  `rows` with eBible's inline Hebrew numbers (`(3-2)`) removed, a Psalm
  title moved to verse 0. `numbers` counts the numbers removed, `titles`
  lists the verse-0 references made, `elsewhere` the numbers the core puts
  in another English verse than eBible's (`{reference, "(20-13)"}`; the
  Decalogue's Hebrew accentuation, Exodus 20:13–16 as one verse): their
  text stays in eBible's verse.
  """
  @spec hebrew_numbers([Usfm.row()], (tuple() -> {integer(), integer()} | nil)) :: %{
          rows: [Usfm.row()],
          numbers: non_neg_integer(),
          titles: [String.t()],
          elsewhere: [{String.t(), String.t()}]
        }
  def hebrew_numbers(rows, english) do
    marker = Regex.compile!("\\(([0-9]+)-([0-9]+)\\)")

    {rows, {numbers, elsewhere}} =
      Enum.map_reduce(rows, {0, []}, fn row, {numbers, elsewhere} ->
        case Regex.scan(marker, row.text, return: :index) do
          [] ->
            {[row], {numbers, elsewhere}}

          found ->
            {split, moved} = split(row, found, english)
            {split, {numbers + length(found), elsewhere ++ moved}}
        end
      end)

    rows = List.flatten(rows)
    duplicates = rows |> Enum.frequencies_by(& &1.reference) |> Enum.filter(&(elem(&1, 1) > 1))
    if duplicates != [], do: raise(ArgumentError, "repeated verses #{inspect(duplicates)}")

    %{
      rows: rows,
      numbers: numbers,
      titles: for(%{verse: 0} = row <- rows, do: row.reference),
      elsewhere: elsewhere
    }
  end

  # The verse's text cut at its Hebrew numbers, each piece placed by the
  # English verse the core gives its Hebrew number (text before the first
  # number belongs to the Hebrew verse before it, else to the first piece),
  # then joined per English verse: this verse, or its chapter's verse 0.
  defp split(row, found, english) do
    numbers =
      Enum.map(found, fn [{start, length}, chapter, verse] ->
        {start, start + length, number(row.text, chapter), number(row.text, verse)}
      end)

    pieces =
      numbers
      |> Enum.with_index()
      |> Enum.map(fn {{start, after_number, chapter, verse}, index} ->
        stop =
          case Enum.at(numbers, index + 1) do
            {next, _, _, _} -> next
            nil -> byte_size(row.text)
          end

        {place(row, english.({row.book, chapter, verse})),
         binary_part(row.text, after_number, stop - after_number),
         binary_part(row.text, start, after_number - start)}
      end)

    {first_start, _, first_chapter, first_verse} = hd(numbers)
    leading = binary_part(row.text, 0, first_start)

    pieces =
      case {String.trim(leading), english.({row.book, first_chapter, first_verse - 1})} do
        {"", _} -> pieces
        {_, nil} -> List.update_at(pieces, 0, fn {at, text, n} -> {at, leading <> text, n} end)
        {_, before} -> [{place(row, before), leading, nil} | pieces]
      end

    moved = for {{:elsewhere, _}, _text, number} <- pieces, number, do: {row.reference, number}

    rows =
      pieces
      |> Enum.map(fn {at, text, _number} -> {verse(row, at), text} end)
      |> Enum.chunk_by(&elem(&1, 0))
      |> Enum.map(fn [{verse, _} | _] = chunk ->
        text = chunk |> Enum.map(&elem(&1, 1)) |> Usfm.finish()
        %{row | reference: "#{row.book}.#{row.chapter}.#{verse}", verse: verse, text: text}
      end)
      |> Enum.reject(&(&1.text == ""))

    {rows, moved}
  end

  # Where a Hebrew verse's text goes: verse 0 of this chapter (from verse 1)
  # is a title; unmapped, this verse or another verse stays in this verse,
  # eBible's English number, another verse noted as `{:elsewhere, _}`.
  defp place(_row, nil), do: :here
  defp place(%{chapter: chapter, verse: verse}, {chapter, verse}), do: :here
  defp place(%{chapter: chapter, verse: 1}, {chapter, 0}), do: :title
  defp place(_row, other), do: {:elsewhere, other}

  defp verse(_row, :title), do: 0
  defp verse(row, _here_or_elsewhere), do: row.verse

  defp number(text, {start, length}), do: String.to_integer(binary_part(text, start, length))
end
