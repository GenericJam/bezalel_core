defmodule Bezalel.Study.Reference do
  @moduledoc """
  Bible references: book names to the packs' book codes, and the reference
  forms the study tools accept ("Ex 31:2-3", "Exodus 31", "Jn 3:16",
  "Luke 19:45-20:2", "Jude 3").

  Ported from studybible-mcp (MIT; `database.py`: `BOOK_ABBREV_MAP`,
  `book_code`, `expand_single_chapter_reference`,
  `StudyBibleDB.parse_passage_reference`, `_normalize_reference`,
  `_THEOGRAPHIC_BOOK_MAP`; `server.py`: `_parse_single_chapter`).
  """

  alias Bezalel.Study.{Format, Patterns}

  @book_codes %{
    "genesis" => "Gen",
    "gen" => "Gen",
    "exodus" => "Exo",
    "exod" => "Exo",
    "ex" => "Exo",
    "leviticus" => "Lev",
    "lev" => "Lev",
    "numbers" => "Num",
    "num" => "Num",
    "deuteronomy" => "Deu",
    "deut" => "Deu",
    "dt" => "Deu",
    "joshua" => "Jos",
    "josh" => "Jos",
    "judges" => "Jdg",
    "judg" => "Jdg",
    "ruth" => "Rut",
    "1 samuel" => "1Sa",
    "1sam" => "1Sa",
    "1 sam" => "1Sa",
    "2 samuel" => "2Sa",
    "2sam" => "2Sa",
    "2 sam" => "2Sa",
    "1 kings" => "1Ki",
    "1kgs" => "1Ki",
    "1 kgs" => "1Ki",
    "2 kings" => "2Ki",
    "2kgs" => "2Ki",
    "2 kgs" => "2Ki",
    "1 chronicles" => "1Ch",
    "1chr" => "1Ch",
    "1 chr" => "1Ch",
    "2 chronicles" => "2Ch",
    "2chr" => "2Ch",
    "2 chr" => "2Ch",
    "ezra" => "Ezr",
    "nehemiah" => "Neh",
    "neh" => "Neh",
    "esther" => "Est",
    "esth" => "Est",
    "job" => "Job",
    "psalms" => "Psa",
    "psalm" => "Psa",
    "ps" => "Psa",
    "proverbs" => "Pro",
    "prov" => "Pro",
    "pr" => "Pro",
    "ecclesiastes" => "Ecc",
    "eccl" => "Ecc",
    "song of solomon" => "Sng",
    "song of songs" => "Sng",
    "song" => "Sng",
    "sos" => "Sng",
    "isaiah" => "Isa",
    "isa" => "Isa",
    "jeremiah" => "Jer",
    "jer" => "Jer",
    "lamentations" => "Lam",
    "lam" => "Lam",
    "ezekiel" => "Ezk",
    "ezek" => "Ezk",
    "eze" => "Ezk",
    "daniel" => "Dan",
    "dan" => "Dan",
    "hosea" => "Hos",
    "hos" => "Hos",
    "joel" => "Jol",
    "amos" => "Amo",
    "obadiah" => "Oba",
    "obad" => "Oba",
    "ob" => "Oba",
    "jonah" => "Jon",
    "micah" => "Mic",
    "mic" => "Mic",
    "nahum" => "Nam",
    "nah" => "Nam",
    "habakkuk" => "Hab",
    "hab" => "Hab",
    "zephaniah" => "Zep",
    "zeph" => "Zep",
    "haggai" => "Hag",
    "hag" => "Hag",
    "zechariah" => "Zec",
    "zech" => "Zec",
    "malachi" => "Mal",
    "mal" => "Mal",
    "matthew" => "Mat",
    "matt" => "Mat",
    "mt" => "Mat",
    "mark" => "Mrk",
    "mk" => "Mrk",
    "luke" => "Luk",
    "lk" => "Luk",
    "john" => "Jhn",
    "jn" => "Jhn",
    "acts" => "Act",
    "romans" => "Rom",
    "rom" => "Rom",
    "1 corinthians" => "1Co",
    "1cor" => "1Co",
    "1 cor" => "1Co",
    "2 corinthians" => "2Co",
    "2cor" => "2Co",
    "2 cor" => "2Co",
    "galatians" => "Gal",
    "gal" => "Gal",
    "ephesians" => "Eph",
    "eph" => "Eph",
    "philippians" => "Php",
    "phil" => "Php",
    "colossians" => "Col",
    "col" => "Col",
    "1 thessalonians" => "1Th",
    "1thess" => "1Th",
    "1 thess" => "1Th",
    "2 thessalonians" => "2Th",
    "2thess" => "2Th",
    "2 thess" => "2Th",
    "1 timothy" => "1Ti",
    "1tim" => "1Ti",
    "1 tim" => "1Ti",
    "2 timothy" => "2Ti",
    "2tim" => "2Ti",
    "2 tim" => "2Ti",
    "titus" => "Tit",
    "philemon" => "Phm",
    "philem" => "Phm",
    "phlm" => "Phm",
    "hebrews" => "Heb",
    "heb" => "Heb",
    "james" => "Jas",
    "jas" => "Jas",
    "1 peter" => "1Pe",
    "1pet" => "1Pe",
    "1 pet" => "1Pe",
    "2 peter" => "2Pe",
    "2pet" => "2Pe",
    "2 pet" => "2Pe",
    "1 john" => "1Jn",
    "1jn" => "1Jn",
    "2 john" => "2Jn",
    "2jn" => "2Jn",
    "3 john" => "3Jn",
    "3jn" => "3Jn",
    "jude" => "Jud",
    "revelation" => "Rev",
    "rev" => "Rev",
    "tobit" => "Tob",
    "tob" => "Tob",
    "judith" => "Jdt",
    "jdt" => "Jdt",
    "wisdom" => "Wis",
    "wisdom of solomon" => "Wis",
    "wis" => "Wis",
    "sirach" => "Sir",
    "ecclesiasticus" => "Sir",
    "sir" => "Sir",
    "baruch" => "Bar",
    "bar" => "Bar",
    "1 maccabees" => "1Ma",
    "1macc" => "1Ma",
    "1 macc" => "1Ma",
    "2 maccabees" => "2Ma",
    "2macc" => "2Ma",
    "2 macc" => "2Ma",
    "3 maccabees" => "3Ma",
    "3macc" => "3Ma",
    "3 macc" => "3Ma",
    "4 maccabees" => "4Ma",
    "4macc" => "4Ma",
    "4 macc" => "4Ma",
    "1 esdras" => "1Es",
    "1esd" => "1Es",
    "1 esd" => "1Es",
    "prayer of manasseh" => "Man",
    "manasseh" => "Man",
    "psalms of solomon" => "Pss",
    "psalm of solomon" => "Pss",
    "greek esther" => "EsG",
    "esther greek" => "EsG",
    "letter of jeremiah" => "Lje",
    "epistle of jeremiah" => "Lje",
    "susanna" => "Sus",
    "bel and the dragon" => "Bel",
    "odes" => "Ode",
    "2 esdras" => "2Es",
    "2esd" => "2Es",
    "2 esd" => "2Es"
  }
  @codes_lower Map.new(Map.values(@book_codes), &{String.downcase(&1), &1})

  # Books with a single chapter, conventionally cited by verse alone ("Jude 3").
  @single_chapter_books MapSet.new(["Oba", "Phm", "2Jn", "3Jn", "Jud"])

  # The packs' book codes as Theographic (the graph pack) writes them.
  @theographic %{
    "1Ch" => "1Chr",
    "1Co" => "1Cor",
    "1Jn" => "1John",
    "1Ki" => "1Kgs",
    "1Pe" => "1Pet",
    "1Sa" => "1Sam",
    "1Th" => "1Thess",
    "1Ti" => "1Tim",
    "2Ch" => "2Chr",
    "2Co" => "2Cor",
    "2Jn" => "2John",
    "2Ki" => "2Kgs",
    "2Pe" => "2Pet",
    "2Sa" => "2Sam",
    "2Th" => "2Thess",
    "2Ti" => "2Tim",
    "3Jn" => "3John",
    "Act" => "Acts",
    "Amo" => "Amos",
    "Deu" => "Deut",
    "Ecc" => "Eccl",
    "Est" => "Esth",
    "Exo" => "Exod",
    "Ezk" => "Ezek",
    "Jdg" => "Judg",
    "Jhn" => "John",
    "Jol" => "Joel",
    "Jon" => "Jonah",
    "Jos" => "Josh",
    "Jud" => "Jude",
    "Luk" => "Luke",
    "Mat" => "Matt",
    "Mrk" => "Mark",
    "Nam" => "Nah",
    "Oba" => "Obad",
    "Phm" => "Phlm",
    "Php" => "Phil",
    "Pro" => "Prov",
    "Psa" => "Ps",
    "Rut" => "Ruth",
    "Sng" => "Song",
    "Tit" => "Titus",
    "Zec" => "Zech",
    "Zep" => "Zeph"
  }

  @typedoc """
  A parsed passage in English numbering. A nil verse means "from the start"
  or "to the end" of its chapter.
  """
  @type passage :: %{
          book: String.t(),
          book_name: String.t(),
          start_chapter: non_neg_integer(),
          start_verse: non_neg_integer() | nil,
          end_chapter: non_neg_integer(),
          end_verse: non_neg_integer() | nil
        }

  @doc """
  The book code of a name, abbreviation or compact form ("1john"), or nil.

      iex> Bezalel.Study.Reference.book_code("Ex")
      "Exo"
      iex> Bezalel.Study.Reference.book_code("1john")
      "1Jn"
  """
  @spec book_code(String.t()) :: String.t() | nil
  def book_code(name) do
    key =
      Regex.replace(Patterns.get(:whitespace), name |> String.trim() |> String.downcase(), " ")

    spaced = Regex.replace(Patterns.get(:leading_digit), key, "\\1 ")

    Enum.find_value([key, spaced, String.replace(key, " ", "")], fn candidate ->
      Map.get(@book_codes, candidate) || Map.get(@codes_lower, candidate)
    end)
  end

  @doc """
  The book code of a name exactly as the abbreviation table spells it
  (case and surrounding space aside), else the name's first three
  characters in title case: studybible-mcp's reading of ANE key references
  ("1 Cor" is 1Co, "Exod" is Exo, "Phm" is Phm).
  """
  @spec abbreviation(String.t()) :: String.t()
  def abbreviation(name) do
    trimmed = String.trim(name)
    Map.get(@book_codes, String.downcase(trimmed)) || prefix_code(trimmed)
  end

  @doc """
  Rewrites a verse-only citation of a single-chapter book as chapter 1:
  "Jude 3" is "Jude 1:3", "Philemon 4-6" is "Philemon 1:4-6". A bare "Jude"
  or "Jude 1" is the chapter ("Jude 1"). Anything else comes back unchanged.
  The tools apply this to every reference argument, as studybible-mcp's
  `call_tool` does.
  """
  @spec expand_single_chapter(String.t()) :: String.t()
  def expand_single_chapter(reference) do
    with %{"book" => book} = match <-
           Regex.named_captures(Patterns.get(:single_chapter), reference),
         true <- MapSet.member?(@single_chapter_books, book_code(book)) do
      book = book |> collapse() |> String.trim()

      case match["verses"] do
        verses when verses in ["", "1"] -> "#{book} 1"
        verses -> "#{book} 1:#{Regex.replace(Patterns.get(:dash), verses, "-")}"
      end
    else
      _ -> reference
    end
  end

  @doc "Is `code` a single-chapter book (Obadiah, Philemon, 2 and 3 John, Jude)?"
  @spec single_chapter_book?(String.t() | nil) :: boolean()
  def single_chapter_book?(code), do: MapSet.member?(@single_chapter_books, code)

  @doc """
  Parses a verse, verse range, cross-chapter range or whole chapter (or
  chapter range: "Psalm 23-24"); nil when the text isn't one of those
  shapes. An unknown book name still parses, to a code with no verses, so
  `lookup_verse` can say the book is unknown.
  """
  @spec parse_passage(String.t()) :: passage() | nil
  def parse_passage(reference) do
    text = Regex.replace(Patterns.get(:dash), String.trim(reference), "-")

    case Regex.named_captures(Patterns.get(:passage), text) do
      nil -> nil
      match -> passage(match)
    end
  end

  defp passage(match) do
    book_name = match["book"] |> collapse() |> String.trim()
    start_chapter = String.to_integer(match["c1"])
    start_verse = integer_or_nil(match["v1"])
    end_chapter = integer_or_nil(match["c2"]) || start_chapter
    end_verse = integer_or_nil(match["v2"])

    {end_chapter, end_verse} =
      cond do
        # "Psalm 23-24": a range of whole chapters.
        end_verse && match["c2"] == "" && start_verse == nil -> {end_verse, nil}
        # A single verse.
        end_verse == nil && start_verse != nil -> {end_chapter, start_verse}
        true -> {end_chapter, end_verse}
      end

    %{
      book: book_code(book_name) || prefix_code(String.replace(book_name, " ", "")),
      book_name: book_name,
      start_chapter: start_chapter,
      start_verse: start_verse,
      end_chapter: end_chapter,
      end_verse: end_verse
    }
  end

  @doc """
  A verse reference in the packs' form ("John 3:16" is "Jhn.3.16"); a range
  gives its first verse. Text that isn't a verse reference comes back
  unchanged (and matches no verse).
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(reference) do
    case Regex.run(Patterns.get(:verse), String.trim(reference)) do
      [_, book, chapter, verse | _] ->
        "#{book_code(book) || prefix_code(book)}.#{chapter}.#{String.downcase(verse)}"

      nil ->
        reference
    end
  end

  @doc """
  `{book code, chapter}` of a whole-chapter reference ("Song of Solomon 2");
  nil for verses, chapter ranges and anything unparseable.
  """
  @spec single_chapter(String.t()) :: {String.t(), pos_integer()} | nil
  def single_chapter(reference) do
    case parse_passage(reference) do
      %{start_verse: nil, start_chapter: chapter, end_chapter: chapter, book: book} ->
        {book, chapter}

      _ ->
        nil
    end
  end

  @doc "A pack reference ('Exo.31.2') or book code in Theographic's form ('Exod.31.2')."
  @spec theographic(String.t()) :: String.t()
  def theographic(reference) do
    [book | rest] = String.split(reference, ".")
    Enum.join([Map.get(@theographic, book, book) | rest], ".")
  end

  @doc "'Jhn.3.16' as 'Jhn 3:16'."
  @spec display(String.t()) :: String.t()
  def display(reference) do
    case String.split(reference, ".") do
      [book, chapter, verse] -> "#{book} #{chapter}:#{verse}"
      _ -> reference
    end
  end

  @doc "An English-numbered span as 'Luke 19:1', 'Luke 19:1-3' or 'Luke 19:45-20:2'."
  @spec label(String.t(), {integer(), integer()}, {integer(), integer()}) :: String.t()
  def label(book_name, {chapter, verse}, {chapter, verse}), do: "#{book_name} #{chapter}:#{verse}"

  def label(book_name, {chapter, verse}, {chapter, end_verse}),
    do: "#{book_name} #{chapter}:#{verse}-#{end_verse}"

  def label(book_name, {chapter, verse}, {end_chapter, end_verse}),
    do: "#{book_name} #{chapter}:#{verse}-#{end_chapter}:#{end_verse}"

  # A name with no entry in the table, as its first three characters in
  # title case (Python's `name[:3].title()`): a prefix match, so "2 Chron"
  # (spaces dropped) is 2Ch and "Genes" is Gen; anything else is a code with
  # no verses.
  defp prefix_code(name), do: name |> String.slice(0, 3) |> Format.title()

  defp collapse(text), do: Regex.replace(Patterns.get(:whitespace), text, " ")

  defp integer_or_nil(""), do: nil
  defp integer_or_nil(nil), do: nil
  defp integer_or_nil(digits), do: String.to_integer(digits)
end
