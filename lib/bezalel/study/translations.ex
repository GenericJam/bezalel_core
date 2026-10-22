defmodule Bezalel.Study.Translations do
  @moduledoc """
  The English translations the study tools can quote: the NET Bible (the
  default), the JPS 1917 and the Literal and Simplified Texts adapted from
  unfoldingWord's ULT and UST (the translations pack, `translation_verses`),
  and the Berean Standard Bible (the core pack, `bsb_verses`). The user
  picks one by key (`Bezalel.Study.Preferences`, `translation`: `net`,
  `bsb`, `jps1917`, `ult`, `ust`); the words and Strong's numbers stay
  STEPBible's either way.

  The NET is quoted by permission for non-commercial use
  (netbible.com/copyright): every quotation is followed by "(NET)", in
  software on the internet with "NET" linked to http://netbible.org, the
  text unaltered, and the acknowledgement (`copyright`) shown. The NET's
  translators' notes are not licensed and are not in the pack.

  The JPS 1917 is public domain and has the Old Testament only. The ULT and
  UST are CC BY-SA 4.0; the pack's text drops their word alignment, so it
  is a derivative, shown, as their licence asks, without the unfoldingWord®
  trademark, saying what changed and crediting the original (`copyright`).
  A release of theirs holds only the books unfoldingWord has finished.

  `with_translation/2` runs a tool call with the translation it quotes: one
  from the pack with one connection to the translations pack for the whole
  call, or the BSB (with a one-line note saying why) when that pack isn't
  readable or lacks the translation. A book the chosen translation doesn't
  have (`books`: `:all`, `:old_testament`, or `:released`, the books in the
  pack) is quoted from the BSB, verse by verse (`Bezalel.Study.Verses`
  marks those rows), and `settle/3` names it in one note.
  """

  alias Bezalel.Study.{DB, Reference}

  @translations [
    %{
      key: "net",
      name: "NET Bible",
      abbreviation: "NET",
      url: "http://netbible.org",
      copyright:
        "Scripture quoted by permission. Quotations designated (NET) are from the NET " <>
          "Bible® copyright ©1996, 2019 by Biblical Studies Press, L.L.C. " <>
          "http://netbible.com All rights reserved.",
      licence: "Free non-commercial use by permission (netbible.com/copyright)",
      books: :all
    },
    %{
      key: "bsb",
      name: "Berean Standard Bible",
      abbreviation: "BSB",
      url: "https://bereanbible.com",
      copyright:
        "The Holy Bible, Berean Standard Bible, BSB is produced in cooperation with Bible " <>
          "Hub, Discovery Bible, unfoldingWord, Bible Aquifer, OpenBible.com, and the Berean " <>
          "Bible Translation Committee. This text of God's Word has been dedicated to the " <>
          "public domain.",
      licence: "Public domain",
      books: :all
    },
    %{
      key: "jps1917",
      name: "JPS 1917",
      abbreviation: "JPS",
      url: "https://ebible.org/find/details.php?id=engjps",
      copyright:
        "The Holy Scriptures according to the Masoretic Text: A New Translation " <>
          "(Jewish Publication Society of America, 1917). Public domain; text from eBible.org.",
      licence: "Public domain",
      books: :old_testament
    },
    %{
      key: "ult",
      name: "Literal Text (ULT, adapted)",
      abbreviation: "ULT",
      url: "https://www.unfoldingword.org/ult",
      copyright:
        "Literal Text (ULT, adapted): adapted from a work copyright © 2022 by unfoldingWord, " <>
          "licensed CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). The " <>
          "original work by unfoldingWord is available from unfoldingword.org/ult. Changes: " <>
          "the word alignment, footnotes and headings are removed, the Psalm titles " <>
          "numbered verse 0 and 2 Corinthians 13:13 numbered 13:14; the verse text is " <>
          "otherwise unaltered. This adaptation is available under the same licence.",
      licence: "CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)",
      books: :released
    },
    %{
      key: "ust",
      name: "Simplified Text (UST, adapted)",
      abbreviation: "UST",
      url: "https://www.unfoldingword.org/ust",
      copyright:
        "Simplified Text (UST, adapted): adapted from a work copyright © 2022 by " <>
          "unfoldingWord, licensed CC BY-SA 4.0 " <>
          "(https://creativecommons.org/licenses/by-sa/4.0/). The original work by " <>
          "unfoldingWord is available from unfoldingword.org/ust. Changes: the word " <>
          "alignment, footnotes and headings are removed, the Psalm titles numbered verse 0 " <>
          "and 2 Corinthians 13:13 numbered 13:14; the verse text is otherwise unaltered. " <>
          "This adaptation is available under the same licence.",
      licence: "CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)",
      books: :released
    }
  ]

  @new_testament ~w(Mat Mrk Luk Jhn Act Rom 1Co 2Co Gal Eph Php Col 1Th 2Th 1Ti 2Ti Tit Phm
                    Heb Jas 1Pe 2Pe 1Jn 2Jn 3Jn Jud Rev)

  @typedoc """
  A translation the tools can quote. `books` says which books it has:
  `:all`, `:old_testament`, or `:released` (those in the translations
  pack). Inside `with_translation/2` a translation from the translations
  pack also carries `conn`, the call's connection to that pack.
  """
  @type t :: %{
          required(:key) => String.t(),
          required(:name) => String.t(),
          required(:abbreviation) => String.t(),
          required(:url) => String.t(),
          required(:copyright) => String.t(),
          required(:licence) => String.t(),
          required(:books) => :all | :old_testament | :released,
          optional(:conn) => DB.conn()
        }

  @typedoc "The translation as a result carries it, for an app to draw the label and link."
  @type ref :: %{key: String.t(), abbreviation: String.t(), url: String.t()}

  @doc "Every translation, the default first."
  @spec all() :: [t()]
  def all, do: @translations

  @doc "The translation keys, the default first."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(@translations, & &1.key)

  @doc "The translation `key`, or nil."
  @spec get(term()) :: t() | nil
  def get(key), do: Enum.find(@translations, &(&1.key == key))

  @doc "`translation` as a result carries it: key, abbreviation and link."
  @spec ref(t()) :: ref()
  def ref(translation), do: Map.take(translation, [:key, :abbreviation, :url])

  @doc """
  The label after a quotation in Markdown: "[NET](http://netbible.org)" (the
  NET's terms ask for the link), else the abbreviation: "BSB", "JPS",
  "ULT", "UST".
  """
  @spec label(t() | ref()) :: String.t()
  def label(%{key: "net", abbreviation: abbreviation, url: url}), do: "[#{abbreviation}](#{url})"
  def label(%{abbreviation: abbreviation}), do: abbreviation

  @doc """
  `fun.(translation, note)` with the translation chosen by `key`, and its
  result. A translation from the translations pack comes with that pack
  opened once here for the whole call (`translation.conn`) and closed after
  `fun`; without a readable pack, or when the pack doesn't have the
  translation (one published before it), `fun` gets the BSB (core pack)
  and a note saying so. The BSB, or an unknown key, is the BSB with no
  note.
  """
  @spec with_translation(String.t(), (t(), String.t() | nil -> result)) :: result
        when result: term()
  def with_translation(key, fun) do
    case get(key) do
      %{key: "bsb"} = bsb ->
        fun.(bsb, nil)

      nil ->
        fun.(get("bsb"), nil)

      translation ->
        case DB.with_pack(:translations, &in_pack(&1, translation, fun)) do
          {:ok, {:missing, note}} -> fun.(get("bsb"), note)
          {:ok, {:ok, result}} -> result
          {:error, _} -> fun.(get("bsb"), missing(translation))
        end
    end
  end

  defp in_pack(conn, %{books: :all} = translation, fun),
    do: {:ok, fun.(Map.put(translation, :conn, conn), nil)}

  defp in_pack(conn, translation, fun) do
    if DB.one(conn, "SELECT 1 AS x FROM translation_verses WHERE translation = ? LIMIT 1", [
         translation.key
       ]),
       do: {:ok, fun.(Map.put(translation, :conn, conn), nil)},
       else: {:missing, outdated(translation)}
  end

  defp missing(translation) do
    "The #{translation.name} isn't on this device (the translations pack isn't " <>
      "downloaded), so this English is the BSB."
  end

  defp outdated(translation) do
    "The #{translation.name} isn't in the translations pack on this device (the pack " <>
      "needs updating), so this English is the BSB."
  end

  @doc """
  Whether `translation` has `book` (a STEP code): every book for `:all`,
  the Old Testament's for `:old_testament`, and for `:released` the books
  with a verse in the translations pack (through the call's `conn`, else
  opening the pack; false when it can't be read).
  """
  @spec covers?(t(), String.t()) :: boolean()
  def covers?(%{books: :all}, _book), do: true
  def covers?(%{books: :old_testament}, book), do: book not in @new_testament

  def covers?(%{books: :released, conn: conn, key: key}, book) do
    # The primary key (translation, reference) answers this from its index.
    DB.one(
      conn,
      "SELECT 1 AS x FROM translation_verses WHERE translation = ? AND reference >= ? " <>
        "AND reference < ? LIMIT 1",
      [key, book <> ".", book <> "/"]
    ) != nil
  end

  def covers?(%{books: :released} = translation, book) do
    case DB.with_pack(:translations, &covers?(Map.put(translation, :conn, &1), book)) do
      {:ok, covered} -> covered
      {:error, _} -> false
    end
  end

  @doc """
  The `books` (STEP codes) `translation` doesn't have (`covers?/2`),
  opening the translations pack once for them when it must be asked.
  """
  @spec lacking(t(), [String.t()]) :: [String.t()]
  def lacking(%{books: :released, conn: _} = translation, books),
    do: Enum.reject(books, &covers?(translation, &1))

  def lacking(%{books: :released} = translation, [_ | _] = books) do
    case DB.with_pack(:translations, &lacking(Map.put(translation, :conn, &1), books)) do
      {:ok, lacking} -> lacking
      {:error, _} -> books
    end
  end

  def lacking(translation, books), do: Enum.reject(books, &covers?(translation, &1))

  @doc """
  The translation a result names, its note, and its verses, once the verses
  are read in `translation` (with `note`, `with_translation/2`'s): verses a
  book the translation lacks put in the BSB (`fallback: true`, as
  `Bezalel.Study.Format.verse_view/1` marks them) add one note naming the
  translation and why; when every verse quoted is such a verse, the result
  is the BSB's and the verses unmarked. `views` may hold nils (a verse not
  found).
  """
  @spec settle(t(), String.t() | nil, [map() | nil]) :: {ref(), String.t() | nil, [map() | nil]}
  def settle(translation, note, views) do
    quoted = Enum.filter(views, &(&1 != nil and &1.translated))

    case Enum.filter(quoted, & &1.fallback) do
      [] ->
        {ref(translation), note, views}

      fallback when length(fallback) == length(quoted) ->
        unmarked = Enum.map(views, &(&1 && %{&1 | fallback: false}))
        {ref(get("bsb")), fallback_note(translation, fallback), unmarked}

      fallback ->
        {ref(translation), fallback_note(translation, fallback), views}
    end
  end

  defp fallback_note(translation, views) do
    books = views |> Enum.map(& &1.book) |> Enum.uniq()

    if translation.books == :old_testament and Enum.all?(books, &(&1 in @new_testament)) do
      "The #{translation.name} covers the Old Testament only; New Testament verses are " <>
        "quoted from the BSB."
    else
      names = Enum.map(books, &(Reference.book_name(&1) || &1))
      which = if match?([_], names), do: "it is", else: "those books are"

      "The #{translation.name} doesn't include #{or_list(names)}, so #{which} quoted from " <>
        "the BSB."
    end
  end

  defp or_list([one]), do: one
  defp or_list(names), do: Enum.join(Enum.drop(names, -1), ", ") <> " or " <> List.last(names)
end
