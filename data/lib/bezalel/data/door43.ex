defmodule Bezalel.Data.Door43 do
  @moduledoc """
  The ULT and UST, unfoldingWord's literal and simplified English
  translations (CC BY-SA 4.0), as `translation_verses` rows, from their
  Door43 repositories at a release tag (`pins.json` → `ult`, `ust`: the
  commit and every file's sha256).

  The books are USFM 3 with every English word aligned to the Hebrew or
  Greek; `Bezalel.Data.Usfm` keeps the words and drops the alignment, the
  footnotes and the headings. That makes the pack's text a derivative work,
  so, as each repository's LICENSE.md asks of one, it is shown without the
  unfoldingWord® trademark (here "Literal Text (ULT, adapted)" and
  "Simplified Text (UST, adapted)"), says what was changed, credits "The
  original work by unfoldingWord is available from unfoldingword.org/ult"
  (`/ust`), and keeps CC BY-SA 4.0 (`translation/1`'s `copyright` and
  `licence`). The build checks LICENSE.md still says so.

  A release holds the books unfoldingWord has finished; the rest are simply
  absent (v91: no Numbers, 1–2 Chronicles, Ecclesiastes, Isaiah, Jeremiah or
  Ezekiel). The study tools quote the BSB for a book a translation lacks,
  with a note (core's `Bezalel.Study.Translations`).
  """

  alias Bezalel.Data.{Books, Net, Usfm}
  alias Bezalel.Study.Translations

  @works %{
    "ult" => %{original: "unfoldingWord® Literal Text", path: "ult"},
    "ust" => %{original: "unfoldingWord® Simplified Text", path: "ust"}
  }

  @licence_text "Creative Commons Attribution-ShareAlike 4.0 International License"

  @doc "The keys of the two translations."
  @spec keys() :: [String.t()]
  def keys, do: ~w(ult ust)

  @doc ~S"""
  A pin's source: the repository at its commit.

      iex> Bezalel.Data.Door43.source(%{"repo" => "https://git.door43.org/unfoldingWord/en_ult", "commit" => "35d2"})
      "https://git.door43.org/unfoldingWord/en_ult/src/commit/35d2"
  """
  @spec source(map()) :: String.t()
  def source(pin), do: "#{pin["repo"]}/src/commit/#{pin["commit"]}"

  @doc """
  One checksum for a release's files (`%{name => sha256}`):
  `Bezalel.Data.Net.digest/1` over the names in order.
  """
  @spec digest(%{String.t() => String.t()}) :: String.t()
  def digest(sha256s), do: sha256s |> Enum.sort() |> Net.digest()

  @doc """
  The `translations` row of `key` (`ult` or `ust`; without the source
  columns): core's `Bezalel.Study.Translations` entry, whose `copyright` is
  the derivative's notice (the original's copyright, the attribution its
  licence words, the changes and the licence).
  """
  @spec translation(String.t()) :: map()
  def translation(key) when is_map_key(@works, key) do
    key
    |> Translations.get()
    |> Map.take(~w(key name abbreviation url copyright licence)a)
  end

  @doc """
  Checks a repository's LICENSE.md is the CC BY-SA 4.0 licence of `key`'s
  work, with the trademark and attribution terms `translation/1` follows.
  """
  @spec check_licence!(String.t(), String.t()) :: :ok
  def check_licence!(key, licence) do
    work = Map.fetch!(@works, key)

    expected = [
      work.original,
      @licence_text,
      "you must remove the unfoldingWord® trademark",
      "The original work by unfoldingWord is available from [unfoldingword.org/#{work.path}]"
    ]

    case Enum.reject(expected, &String.contains?(licence, &1)) do
      [] -> :ok
      missing -> raise ArgumentError, "#{key} LICENSE.md lacks #{inspect(missing)}"
    end
  end

  @doc """
  The book files' names in a release's file list: `NN-BBB.usfm` for a book
  of the 66 (front matter, `A0-FRT.usfm`, isn't verse text).
  """
  @spec book_file?(String.t()) :: boolean()
  def book_file?(name) do
    case Regex.run(Regex.compile!("^[0-9]{2}-([0-9A-Z]{3})\\.usfm$"), name) do
      [_, usfm] -> Books.from_usfm(usfm) != nil
      nil -> false
    end
  end

  # Where unfoldingWord's versification (`ufw`) numbers a verse other than
  # the packs' English numbering, the source verse and the packs' verse.
  # 2 Corinthians 13: ufw's 13:12 holds the greetings (the packs' 13:12–13,
  # kept whole there, as a bridge is) and its 13:13 the grace, the packs'
  # 13:14 (the core pack's row '2Co.13.13[13.14]').
  @renumbered %{"2Co.13.13" => {"2Co", 13, 14}}

  @doc """
  Every book's rows in canonical order (`files`: `%{"01-GEN.usfm" =>
  text}`), with what `Bezalel.Data.Usfm` dropped, the books present, and
  the verses moved to the packs' numbering (`renumbered`, `{from, to}`; a
  source that already has the target verse stops the build).
  """
  @spec rows(%{String.t() => String.t()}) :: map()
  def rows(files) do
    by_book =
      for {name, text} <- files, book_file?(name), into: %{} do
        usfm = name |> String.slice(3, 3)
        {Books.from_usfm(usfm), {usfm, text}}
      end

    books =
      for {code, _name, _chapters} <- Books.all(),
          {usfm, text} = by_book[code] || {nil, nil},
          usfm do
        Usfm.book(text, usfm, code)
      end

    {rows, renumbered} = renumber(Enum.flat_map(books, & &1.rows))

    %{
      books: Enum.map(books, &hd(&1.rows).book),
      rows: rows,
      empty: Enum.flat_map(books, & &1.empty),
      headings: Enum.flat_map(books, & &1.headings),
      footnotes: Enum.flat_map(books, & &1.footnotes),
      bridges: Enum.flat_map(books, & &1.bridges),
      renumbered: renumbered
    }
  end

  defp renumber(rows) do
    present = MapSet.new(rows, & &1.reference)

    Enum.map_reduce(rows, [], fn row, moved ->
      case @renumbered[row.reference] do
        nil -> {row, moved}
        target -> move(row, target, present, moved)
      end
    end)
  end

  defp move(row, {book, chapter, verse}, present, moved) do
    to = "#{book}.#{chapter}.#{verse}"

    if MapSet.member?(present, to),
      do: raise(ArgumentError, "#{row.reference}: #{to} is already in the source")

    {%{row | reference: to, chapter: chapter, verse: verse}, moved ++ [{row.reference, to}]}
  end
end
