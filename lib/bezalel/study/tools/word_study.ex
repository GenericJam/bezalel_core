defmodule Bezalel.Study.Tools.WordStudy do
  @moduledoc """
  `word_study`: the lexicon entry for a Strong's number or a word, with
  five example verses.

  Ported from studybible-mcp's `handle_word_study` (MIT); same text.
  `result/1` returns the entry row and the example verses as data.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Lexicon, Verses}

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
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, {:details, render(result), result}}
  end

  @typedoc "The entry (a lexicon row; nil when a word matched none) and its example verses."
  @type t :: %{entry: DB.row() | nil, examples: [Format.verse_view()]}

  @doc """
  The entry `args` asks for. An unknown Strong's number is an error; a
  word that matches no entry is `%{entry: nil}`.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    strongs = Args.optional(args, "strongs")
    word = Args.optional(args, "word")

    # As studybible-mcp: absent is Greek, null is both languages.
    language =
      case Map.fetch(args, "language") do
        {:ok, language} when is_binary(language) or is_nil(language) -> language
        _ -> "greek"
      end

    cond do
      strongs ->
        with {:ok, %{entry: nil}} <- DB.with_pack(:core, &study(&1, strongs, nil)),
             do: {:error, not_found()}

      word ->
        DB.with_pack(:core, &study(&1, nil, {word, language}))

      true ->
        {:error, "Please provide either 'strongs' number or 'word' to study."}
    end
  end

  defp study(conn, strongs, word) do
    entry =
      case word do
        nil -> Lexicon.entry(conn, strongs)
        {word, language} -> conn |> Lexicon.search(word, language, 1) |> List.first()
      end

    examples =
      if entry,
        do:
          conn
          |> Verses.with_strongs(entry["strongs"], @examples)
          |> Enum.map(&Format.verse_view/1),
        else: []

    %{entry: entry, examples: examples}
  end

  defp not_found, do: "No entry found for the given word/Strong's number."

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{entry: nil}), do: not_found()

  def render(%{entry: entry, examples: []}), do: Format.lexicon_entry(entry)

  def render(%{entry: entry, examples: examples}) do
    bsb = Format.bsb_label(examples)

    Format.lexicon_entry(entry) <>
      "\n\n## Example Passages#{bsb}\n" <>
      Enum.map_join(examples, &"\n**#{&1.reference}**: #{&1.english}\n")
  end
end
