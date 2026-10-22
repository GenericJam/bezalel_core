defmodule Bezalel.Data.Books do
  @moduledoc """
  The 66 books of the Protestant canon in canonical order: the STEP book
  code the study packs use (`verses.book`, `bsb_verses.book`, references
  like `Gen.1.1`), the English name the NET Bible API (labs.bible.org)
  takes and returns, and the number of chapters.
  """

  @books [
    {"Gen", "Genesis", 50},
    {"Exo", "Exodus", 40},
    {"Lev", "Leviticus", 27},
    {"Num", "Numbers", 36},
    {"Deu", "Deuteronomy", 34},
    {"Jos", "Joshua", 24},
    {"Jdg", "Judges", 21},
    {"Rut", "Ruth", 4},
    {"1Sa", "1 Samuel", 31},
    {"2Sa", "2 Samuel", 24},
    {"1Ki", "1 Kings", 22},
    {"2Ki", "2 Kings", 25},
    {"1Ch", "1 Chronicles", 29},
    {"2Ch", "2 Chronicles", 36},
    {"Ezr", "Ezra", 10},
    {"Neh", "Nehemiah", 13},
    {"Est", "Esther", 10},
    {"Job", "Job", 42},
    {"Psa", "Psalms", 150},
    {"Pro", "Proverbs", 31},
    {"Ecc", "Ecclesiastes", 12},
    {"Sng", "Song of Songs", 8},
    {"Isa", "Isaiah", 66},
    {"Jer", "Jeremiah", 52},
    {"Lam", "Lamentations", 5},
    {"Ezk", "Ezekiel", 48},
    {"Dan", "Daniel", 12},
    {"Hos", "Hosea", 14},
    {"Jol", "Joel", 3},
    {"Amo", "Amos", 9},
    {"Oba", "Obadiah", 1},
    {"Jon", "Jonah", 4},
    {"Mic", "Micah", 7},
    {"Nam", "Nahum", 3},
    {"Hab", "Habakkuk", 3},
    {"Zep", "Zephaniah", 3},
    {"Hag", "Haggai", 2},
    {"Zec", "Zechariah", 14},
    {"Mal", "Malachi", 4},
    {"Mat", "Matthew", 28},
    {"Mrk", "Mark", 16},
    {"Luk", "Luke", 24},
    {"Jhn", "John", 21},
    {"Act", "Acts", 28},
    {"Rom", "Romans", 16},
    {"1Co", "1 Corinthians", 16},
    {"2Co", "2 Corinthians", 13},
    {"Gal", "Galatians", 6},
    {"Eph", "Ephesians", 6},
    {"Php", "Philippians", 4},
    {"Col", "Colossians", 4},
    {"1Th", "1 Thessalonians", 5},
    {"2Th", "2 Thessalonians", 3},
    {"1Ti", "1 Timothy", 6},
    {"2Ti", "2 Timothy", 4},
    {"Tit", "Titus", 3},
    {"Phm", "Philemon", 1},
    {"Heb", "Hebrews", 13},
    {"Jas", "James", 5},
    {"1Pe", "1 Peter", 5},
    {"2Pe", "2 Peter", 3},
    {"1Jn", "1 John", 5},
    {"2Jn", "2 John", 1},
    {"3Jn", "3 John", 1},
    {"Jud", "Jude", 1},
    {"Rev", "Revelation", 22}
  ]

  @order @books
         |> Enum.with_index()
         |> Map.new(fn {{code, _name, _chapters}, index} -> {code, index} end)

  @doc "`{step_code, name, chapters}` for the 66 books, in canonical order."
  @spec all() :: [{String.t(), String.t(), pos_integer()}]
  def all, do: @books

  @doc """
  A STEP book code's position in canonical order.

      iex> Bezalel.Data.Books.index("Gen")
      0
      iex> Bezalel.Data.Books.index("Rev")
      65
  """
  @spec index(String.t()) :: non_neg_integer()
  def index(code), do: Map.fetch!(@order, code)

  @usfm Map.new(@books, fn {code, _name, _chapters} -> {String.upcase(code), code} end)

  @doc """
  The STEP code of a USFM book code (the codes are the same in capitals),
  or nil for a book outside the 66.

      iex> Bezalel.Data.Books.from_usfm("EZK")
      "Ezk"
      iex> Bezalel.Data.Books.from_usfm("FRT")
      nil
  """
  @spec from_usfm(String.t()) :: String.t() | nil
  def from_usfm(usfm), do: Map.get(@usfm, usfm)
end
