defmodule Bezalel.Study.Tools.WordStudy do
  @moduledoc """
  `word_study`: the lexicon entry for a Strong's number or a word, with
  five example verses in the user's translation.

  Ported from studybible-mcp's `handle_word_study` (MIT); same text.
  `result/1` returns the entry row and the example verses as data, with
  the translation they are quoted in, and the UBS dictionaries' entries
  for its number when the optional dictionaries pack is installed.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{
    Args,
    Citation,
    Citations,
    DB,
    Dictionaries,
    Format,
    Lexicon,
    Preferences,
    Translations,
    Verses
  }

  @examples 5

  @impl true
  def name, do: "word_study"

  @impl true
  def description do
    """
    Look up the lexicon entry for a Strong's number, or for a Greek, Hebrew, or English word.

    Given a Strong's number (G26, H430) the entry is returned directly; given an
    English word, the most relevant Greek or Hebrew term is resolved first.

    Returns:
    - The word in its original script (e.g. ἀγάπη, אֱלֹהִים)
    - Transliteration and pronunciation
    - Strong's number
    - Brief and full definitions (LSJ for Greek, BDB for Hebrew, plus Abbott-Smith
      for NT Greek where available)
    - Etymology, semantic range, and related words
    - Where the dictionaries pack is installed, the UBS dictionaries' meanings
      (Semantic Dictionary of Biblical Hebrew; Louw & Nida for NT Greek) with their
      semantic domains and glosses
    - Occurrence counts and representative passages

    Relevant for questions about a specific original-language term, a theological
    term's underlying vocabulary, or the semantic range behind an English rendering.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "strongs" => %{
          "type" => "string",
          "description" => "Strong's number (e.g., 'G26' for agapē, 'H3068' for YHWH)"
        },
        "word" => %{
          "type" => "string",
          "description" =>
            "English word to study (e.g., 'love', 'faith'). Will find the most relevant Greek/Hebrew term."
        },
        "language" => %{
          "type" => "string",
          "enum" => ["greek", "hebrew"],
          "description" => "Language to search if using 'word' parameter. Default: greek"
        }
      }
    }
  end

  @doc "The Markdown for the model, with `result/1`'s data for the screens (rho's tool details)."
  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)),
         do: Citations.details(render(result), result, citations(result))
  end

  @typedoc """
  The entry (a lexicon row; nil when a word matched none) and its example
  verses, in `translation` (`translation_note` says why it isn't the one
  chosen; nil when it is); `dictionary` the UBS dictionaries' entries for
  its Strong's number (`Bezalel.Study.Dictionaries.entries/1`: none without
  the dictionaries pack).
  """
  @type t :: %{
          entry: DB.row() | nil,
          examples: [Format.verse_view()],
          dictionary: %{entries: [Dictionaries.entry()], more: non_neg_integer()},
          translation: Translations.ref(),
          translation_note: String.t() | nil
        }

  @doc "The entry `args` asks for, under the host's current preferences (`result/2`)."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc """
  The entry `args` asks for, its examples in `prefs`' translation. An
  unknown Strong's number is an error; a word that matches no entry is
  `%{entry: nil}`.
  """
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    strongs = Args.optional(args, "strongs")
    word = Args.optional(args, "word")

    # As studybible-mcp: absent is Greek, null is both languages.
    language =
      case Map.fetch(args, "language") do
        {:ok, language} when is_binary(language) or is_nil(language) -> language
        _ -> "greek"
      end

    query =
      cond do
        strongs -> {strongs, nil}
        word -> {nil, {word, language}}
        true -> nil
      end

    if query,
      do: Translations.with_translation(prefs.translation, &study(query, &1, &2)),
      else: {:error, "Please provide either 'strongs' number or 'word' to study."}
  end

  defp study({strongs, word}, translation, note) do
    case DB.with_pack(:core, &study(&1, strongs, word, translation)) do
      {:ok, %{entry: nil}} when strongs != nil ->
        {:error, not_found()}

      {:ok, study} ->
        {quoted, note, examples} = Translations.settle(translation, note, study.examples)

        {:ok,
         Map.merge(study, %{
           dictionary: Dictionaries.entries(study.entry && study.entry["strongs"]),
           examples: examples,
           translation: quoted,
           translation_note: note
         })}

      error ->
        error
    end
  end

  defp study(conn, strongs, word, translation) do
    entry =
      case word do
        nil -> Lexicon.entry(conn, strongs)
        {word, language} -> conn |> Lexicon.search(word, language, 1) |> List.first()
      end

    examples =
      if entry,
        do:
          conn
          |> Verses.with_strongs(entry["strongs"], @examples, translation)
          |> Enum.map(&Format.verse_view/1),
        else: []

    %{entry: entry, examples: examples}
  end

  defp not_found, do: "No entry found for the given word/Strong's number."

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{entry: nil}), do: not_found()

  def render(%{entry: entry, examples: []} = result), do: entry_text(entry) <> ubs_text(result)

  def render(%{entry: entry, examples: examples} = result) do
    label = Format.translation_label(examples, result.translation)

    entry_text(entry) <>
      ubs_text(result) <>
      "\n\n## Example Passages#{label}\n" <>
      Format.translation_note(result.translation_note) <>
      Enum.map_join(examples, fn view ->
        "\n**#{view.reference}**#{Format.fallback_label(view)}: #{view.english}\n" <>
          Citation.source_line(example_citation(view, result.translation)) <> "\n"
      end)
  end

  defp entry_text(entry),
    do: Format.lexicon_entry(entry) <> Citation.source_line(entry_citations(entry, :full))

  # The UBS dictionaries' meanings, after the lexicon entry; nothing without them.
  defp ubs_text(result) do
    case result |> dictionary() |> Dictionaries.section() do
      "" -> ""
      section -> "\n" <> String.trim_trailing(section)
    end
  end

  defp dictionary(result), do: Map.get(result, :dictionary, %{entries: [], more: 0})

  @doc """
  The sources `render/1` shows, in its order: the lexicon entry
  (`entry_citations/2`), each UBS dictionary entry, then each example
  verse in the quoted translation (STEP Bible's for a verse shown in
  STEPBible's gloss).
  """
  @spec citations(t()) :: [Citation.t()]
  def citations(%{entry: nil}), do: []

  def citations(%{entry: entry, examples: examples, translation: translation} = result) do
    entry_citations(entry, :full) ++
      Enum.map(dictionary(result).entries, &Dictionaries.citation/1) ++
      Enum.map(examples, &example_citation(&1, translation))
  end

  defp example_citation(view, translation),
    do: Citations.scripture(view.reference, Format.quoted(view, translation))

  @doc """
  A lexicon entry's sources, for the definitions shown: `:full` as
  `Format.lexicon_entry/1` shows them (STEPBible's brief definition when
  it differs from the full one or stands alone, the full BDB (Hebrew) or
  LSJ (Greek) entry, Abbott-Smith's), `:brief` the brief definition alone
  (as `search_lexicon` and `search_by_strongs` show it); then the Strong's
  number's page. An entry the core pack keys `"AS_<lemma>"` (Abbott-Smith's,
  with no Strong's number) cites Abbott-Smith alone, its only source.
  """
  @spec entry_citations(DB.row(), :full | :brief) :: [Citation.t()]
  def entry_citations(entry, shown) do
    if Citations.strongs?(entry["strongs"]),
      do: strongs_citations(entry, shown),
      else: [Citations.abbott_smith(Format.s(entry["strongs"]), Format.s(entry["word"]))]
  end

  # An entry keyed by its Strong's number: the lexicons its shown definitions
  # come from, and the number's page.
  defp strongs_citations(entry, shown) do
    strongs = entry["strongs"]
    word = Format.s(entry["word"])
    short = Format.s(entry["short_definition"])
    full = if shown == :full, do: Format.s(entry["full_definition"]), else: ""

    brief =
      if short != "" and short != full, do: [Citations.step_lexicon(strongs, word)], else: []

    full_entry =
      cond do
        full == "" -> []
        String.starts_with?(String.upcase(strongs), "H") -> [Citations.bdb(strongs, word)]
        true -> [Citations.lsj(strongs, word)]
      end

    abbott_smith =
      if shown == :full and Format.present?(entry["abbott_smith_def"]),
        do: [Citations.abbott_smith(strongs, word)],
        else: []

    brief ++ full_entry ++ abbott_smith ++ [Citations.strongs(strongs, word)]
  end
end
