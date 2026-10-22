defmodule Bezalel.Study.Verses do
  @moduledoc """
  Verse queries on the core pack: a verse by reference, a passage, a
  book's chapter bounds, the verses with a Strong's number, and each row's
  English in the chosen translation (`text_translation`, see
  `attach_english/3`).

  Ported from studybible-mcp's `database.py` (MIT): `get_verse`,
  `get_passage`, `get_chapter_verse_bounds`, `get_verses_with_strongs`,
  `attach_bsb_text`. The English is the BSB (core pack) or the NET
  (translations pack), by `Bezalel.Study.Translations`; every row gets
  `text_translation` (nil where the translation lacks the verse).
  """

  alias Bezalel.Study.{DB, Lexicon, Patterns, Reference, Translations}

  @doc """
  The verse `reference` names ("John 3:16"; a range gives its first verse):
  the row with that reference, else the first row with its book, chapter
  and English verse number, so a verse stored with split numbering
  ('Gen.32.1(32.2)') is found. Never a neighbour: a verse not in the pack
  is nil.
  """
  @spec get(DB.conn(), String.t(), Translations.t()) :: DB.row() | nil
  def get(conn, reference, translation) do
    normalized = Reference.normalize(reference)

    row =
      DB.one(conn, "SELECT * FROM verses WHERE reference = ?", [normalized]) ||
        by_number(conn, normalized)

    if row, do: hd(attach_english(conn, [row], translation))
  end

  # A number beyond SQLite's 64-bit range can't be bound, and names no verse.
  @max_number 0x7FFFFFFFFFFFFFFF

  defp by_number(conn, normalized) do
    with [book, chapter, verse] <- String.split(normalized, "."),
         {chapter, ""} when chapter in 0..@max_number//1 <- Integer.parse(chapter),
         {verse, ""} when verse in 0..@max_number//1 <- Integer.parse(verse) do
      DB.one(
        conn,
        "SELECT * FROM verses WHERE book = ? AND chapter = ? AND verse = ? ORDER BY id LIMIT 1",
        [book, chapter, verse]
      )
    else
      _ -> nil
    end
  end

  @doc "Each chapter of `book` with its first and last English verse number."
  @spec chapter_bounds(DB.conn(), String.t()) :: %{integer() => {integer(), integer()}}
  def chapter_bounds(conn, book) do
    conn
    |> DB.all(
      "SELECT chapter, MIN(verse) AS first, MAX(verse) AS last FROM verses WHERE book = ? GROUP BY chapter",
      [book]
    )
    |> Map.new(&{&1["chapter"], {&1["first"], &1["last"]}})
  end

  @doc """
  The rows of an English-numbered passage in canonical order. Matches the
  book, chapter and verse columns, so OT rows stored with split numbering
  ('Psa.40.6(40.7)') are found, and a verse stored as several rows returns
  all of them.
  """
  @spec passage(
          DB.conn(),
          String.t(),
          {integer(), integer()},
          {integer(), integer()},
          Translations.t()
        ) :: [DB.row()]
  def passage(conn, book, {start_chapter, start_verse}, {end_chapter, end_verse}, translation) do
    rows =
      DB.all(
        conn,
        """
        SELECT * FROM verses
        WHERE book = ?
          AND chapter BETWEEN ? AND ?
          AND (chapter > ? OR verse >= ?)
          AND (chapter < ? OR verse <= ?)
        ORDER BY chapter, verse, id
        """,
        [
          book,
          start_chapter,
          end_chapter,
          start_chapter,
          start_verse,
          end_chapter,
          end_verse
        ]
      )

    attach_english(conn, rows, translation)
  end

  @doc """
  Verses whose words carry `strongs`, at most `limit`. Word data keeps
  STEPBible's one-letter sense suffix (H0430G), so a bare number also
  matches its suffixed forms; a suffixed number matches only itself.
  """
  @spec with_strongs(DB.conn(), String.t(), pos_integer(), Translations.t()) :: [DB.row()]
  def with_strongs(conn, strongs, limit, translation) do
    strongs = Lexicon.normalize_strongs(strongs)

    patterns =
      if Regex.match?(Patterns.get(:strongs_bare), strongs),
        do: [~s(%"#{strongs}"%), ~s(%"#{strongs}_"%)],
        else: [~s(%"#{strongs}"%)]

    where = Enum.map_join(patterns, " OR ", fn _ -> "word_data LIKE ?" end)
    rows = DB.all(conn, "SELECT * FROM verses WHERE #{where} LIMIT ?", patterns ++ [limit])
    attach_english(conn, rows, translation)
  end

  @doc """
  The verse rows from id `first` to `last` (a passage's span), at most
  `limit`, with the columns a preview shows.
  """
  @spec span(DB.conn(), integer(), integer(), pos_integer(), Translations.t()) :: [DB.row()]
  def span(conn, first, last, limit, translation) do
    rows =
      DB.all(
        conn,
        "SELECT reference, book, chapter, verse, text_english FROM verses WHERE id BETWEEN ? AND ? ORDER BY id LIMIT ?",
        [first, last, limit]
      )

    attach_english(conn, rows, translation)
  end

  @doc """
  Sets `text_translation` on each verse row (of the core pack, `conn`): the
  `translation`'s text of the verse with the same reference, the BSB from
  the core pack, the NET from the translations pack through
  `translation.conn`, the connection `Translations.with_translation/2`
  opened for the call (without one, the pack is opened for this lookup; a
  pack that can't be read leaves every verse without text, so the tools
  show the gloss). `translation_verses` use the core pack's references.
  A split-numbered row matches by its English numbering
  ('Gen.32.1(32.2)' is 'Gen.32.1'), except that a row sharing its English
  verse with a plain-reference row gets nil (the plain row carries the
  text: '1Sa.20.42(21.1)' beside '1Sa.20.42'), and an NT row whose
  bracketed verse has no row of its own is that verse ('2Co.13.13[13.14]'
  is '2Co.13.14'). nil also marks the verses the translation omits (and,
  in the BSB, the Psalm superscriptions). A verse in a book the translation
  doesn't have (`Translations.covers?/2`: the JPS's New Testament, a book
  not yet in a ULT or UST release) gets the BSB's text, with
  `text_fallback` true (false on every other row).
  """
  @spec attach_english(DB.conn(), [DB.row()], Translations.t()) :: [DB.row()]
  def attach_english(_conn, [], _translation), do: []

  def attach_english(conn, rows, translation) do
    split =
      for {row, index} <- Enum.with_index(rows),
          match = Regex.run(Patterns.get(:split_reference), row["reference"]),
          into: %{},
          do: {index, match}

    plain = plain_references(conn, split)

    wanted =
      rows
      |> Enum.with_index()
      |> Map.new(fn {row, index} ->
        case split[index] do
          nil -> {index, row["reference"]}
          match -> {index, english_reference(conn, match, plain)}
        end
      end)

    references = wanted |> Map.values() |> Enum.reject(&is_nil/1)
    texts = texts(conn, translation, references)
    borrowed = borrowed(conn, translation, Enum.reject(references, &Map.has_key?(texts, &1)))

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      reference = wanted[index]

      row
      |> Map.put("text_translation", texts[reference] || borrowed[reference])
      |> Map.put(
        "text_fallback",
        not Map.has_key?(texts, reference) and Map.has_key?(borrowed, reference)
      )
    end)
  end

  # The BSB's text of the references in books `translation` doesn't have.
  defp borrowed(_conn, %{books: :all}, _references), do: %{}
  defp borrowed(_conn, _translation, []), do: %{}

  defp borrowed(conn, translation, references) do
    lacking = Translations.lacking(translation, references |> Enum.map(&book/1) |> Enum.uniq())

    case Enum.filter(references, &(book(&1) in lacking)) do
      [] -> %{}
      references -> texts(conn, Translations.get("bsb"), references)
    end
  end

  defp book(reference), do: reference |> String.split(".", parts: 2) |> hd()

  defp plain_references(_conn, split) when map_size(split) == 0, do: MapSet.new()

  defp plain_references(conn, split) do
    english = split |> Map.values() |> Enum.map(&english/1) |> Enum.uniq()

    conn
    |> DB.all(
      "SELECT reference FROM verses WHERE reference IN (#{DB.placeholders(english)})",
      english
    )
    |> MapSet.new(& &1["reference"])
  end

  defp english([_, book, chapter, verse | _]), do: "#{book}.#{chapter}.#{verse}"

  defp english_reference(conn, [_, book, _, _, bracket, chapter, verse] = match, plain) do
    cond do
      MapSet.member?(plain, english(match)) ->
        nil

      bracket == "[" and
          DB.one(
            conn,
            "SELECT 1 FROM verses WHERE book = ? AND chapter = ? AND verse = ? LIMIT 1",
            [book, String.to_integer(chapter), String.to_integer(verse)]
          ) == nil ->
        "#{book}.#{chapter}.#{verse}"

      true ->
        english(match)
    end
  end

  defp texts(_conn, _translation, []), do: %{}

  defp texts(conn, %{key: "bsb"}, references) do
    references = Enum.uniq(references)

    conn
    |> DB.all(
      "SELECT reference, text FROM bsb_verses WHERE reference IN (#{DB.placeholders(references)})",
      references
    )
    |> Map.new(&{&1["reference"], &1["text"]})
  end

  defp texts(_conn, translation, references) do
    references = Enum.uniq(references)

    sql =
      "SELECT reference, text FROM translation_verses WHERE translation = ? " <>
        "AND reference IN (#{DB.placeholders(references)})"

    params = [translation.key | references]

    rows =
      case translation do
        %{conn: tconn} ->
          DB.all(tconn, sql, params)

        _ ->
          case DB.with_pack(:translations, &DB.all(&1, sql, params)) do
            {:ok, rows} -> rows
            {:error, _} -> []
          end
      end

    Map.new(rows, &{&1["reference"], &1["text"]})
  end
end
