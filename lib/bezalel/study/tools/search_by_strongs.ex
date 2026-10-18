defmodule Bezalel.Study.Tools.SearchByStrongs do
  @moduledoc """
  `search_by_strongs`: the verses where a Greek or Hebrew word (by Strong's
  number) appears.

  Ported from studybible-mcp's `handle_search_by_strongs` (MIT); same
  text, the verses in the user's translation, and as many as the user's
  default result count unless `limit` says. `result/1` returns the lexicon
  row and the verses.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{
    Args,
    Citation,
    Citations,
    DB,
    Format,
    Lexicon,
    Preferences,
    Translations,
    Verses
  }

  alias Bezalel.Study.Tools.WordStudy

  @impl true
  def name, do: "search_by_strongs"

  @impl true
  def description do
    """
    Search by Strong's number for every verse where that word appears.

    Takes a Strong's number (typically obtained from `word_study` or
    `search_lexicon`) and returns the passages containing that Greek or Hebrew word,
    showing how biblical authors used it in context and the range of senses it
    carries across occurrences.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "strongs" => %{
          "type" => "string",
          "description" => "Strong's number (e.g., 'G26', 'H430')"
        },
        "limit" => %{
          "type" => "integer",
          "description" =>
            "Maximum verses to return. Default: the user's setting (8 unless changed)"
        }
      },
      "required" => ["strongs"]
    }
  end

  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)),
         do: Citations.details(render(result), result, citations(result))
  end

  @typedoc """
  `strongs` as given, its lexicon entry, and the verses that carry it, in
  `translation` (`translation_note`: why it isn't the one chosen, or nil).
  """
  @type t :: %{
          strongs: String.t(),
          entry: DB.row(),
          verses: [Format.verse_view()],
          translation: Translations.ref(),
          translation_note: String.t() | nil
        }

  @doc "The verses with `args`' Strong's number, under the host's current preferences."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc "The verses with `args`' Strong's number under `prefs`; an unknown number is an error."
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    case Args.string(args, "strongs") do
      "" ->
        {:error, "Please provide a Strong's number (e.g., 'G26' or 'H3068')."}

      strongs ->
        limit = Args.limit(args, Preferences.limit(prefs, nil))
        Translations.with_translation(prefs.translation, &verses(strongs, limit, &1, &2))
    end
  end

  defp verses(strongs, limit, translation, note) do
    case DB.with_pack(:core, &search(&1, strongs, limit, translation)) do
      {:ok, nil} ->
        {:error, "Unknown Strong's number: #{strongs}"}

      {:ok, result} ->
        {:ok,
         Map.merge(result, %{translation: Translations.ref(translation), translation_note: note})}

      error ->
        error
    end
  end

  defp search(conn, strongs, limit, translation) do
    if entry = Lexicon.entry(conn, strongs) do
      verses =
        conn
        |> Verses.with_strongs(strongs, limit, translation)
        |> Enum.map(&Format.verse_view/1)

      %{strongs: strongs, entry: entry, verses: verses}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{strongs: strongs, entry: entry, verses: verses} = result) do
    label = Format.translation_label(verses, result.translation)

    body =
      if verses == [],
        do: "No verses found with this Strong's number in the database.\n",
        else:
          Enum.map_join(verses, fn view ->
            "**#{view.reference}**: #{view.english}\n" <>
              Citation.source_line(verse_citation(view, result.translation)) <> "\n\n"
          end)

    "## Verses with #{strongs} (#{Format.s(entry["word"])} - #{Format.s(entry["transliteration"])})#{label}\n\n" <>
      Format.translation_note(result.translation_note) <>
      "*#{Format.s(entry["short_definition"])}*\n" <>
      Citation.source_line(WordStudy.entry_citations(entry, :brief)) <> "\n\n" <> body
  end

  @doc """
  The sources `render/1` shows, in its order: the entry's brief definition
  and Strong's page, then each verse in the quoted translation (STEP
  Bible's for a verse shown in STEPBible's gloss).
  """
  @spec citations(t()) :: [Citation.t()]
  def citations(%{entry: entry, verses: verses, translation: translation}) do
    WordStudy.entry_citations(entry, :brief) ++ Enum.map(verses, &verse_citation(&1, translation))
  end

  defp verse_citation(view, translation),
    do: Citations.scripture(view.reference, if(view.translated, do: translation))
end
