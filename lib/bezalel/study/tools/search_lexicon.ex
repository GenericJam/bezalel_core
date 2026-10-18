defmodule Bezalel.Study.Tools.SearchLexicon do
  @moduledoc """
  `search_lexicon`: the Greek and Hebrew entries an English word,
  transliteration or concept matches.

  Ported from studybible-mcp's `handle_search_lexicon` (MIT); same text.
  `result/1` returns the matching lexicon rows.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Lexicon, Preferences}

  @impl true
  def name, do: "search_lexicon"

  @impl true
  def description do
    """
    Search the Greek and Hebrew lexicons by English word, transliteration, or concept.

    Returns the matching lexicon entries ranked by relevance — typically several
    distinct original-language words that an English term covers (e.g. "love" →
    agapē, phileō, erōs), each with its Strong's number, definition, and semantic
    range.

    Relevant for identifying which original-language terms lie behind an English
    word or a biblical concept, and for distinguishing between near-synonyms.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search term (English word, transliteration, or concept)"
        },
        "language" => %{
          "type" => "string",
          "enum" => ["greek", "hebrew"],
          "description" => "Limit search to one language. Omit to search both."
        },
        "limit" => %{
          "type" => "integer",
          "description" =>
            "Maximum results to return. Default: the user's setting (8 unless changed)"
        }
      },
      "required" => ["query"]
    }
  end

  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)), do: {:ok, render(result)}
  end

  @type t :: %{query: String.t(), entries: [DB.row()]}

  @doc "The entries matching `args`' query, under the host's current preferences."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc "The entries matching `args`' query (possibly none), as many as `prefs` say by default."
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    case Args.string(args, "query") do
      "" ->
        {:error, "Please provide a search query."}

      query ->
        language = Args.optional(args, "language")
        limit = Args.limit(args, Preferences.limit(prefs, nil))

        with {:ok, entries} <-
               DB.with_pack(:core, &Lexicon.search(&1, query, language, limit)),
             do: {:ok, %{query: query, entries: entries}}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{query: query, entries: []}), do: "No entries found for '#{query}'."

  def render(%{query: query, entries: entries}) do
    "## Lexicon Search: '#{query}'\n\nFound #{length(entries)} entries:\n\n" <>
      Enum.map_join(entries, fn entry ->
        "### #{entry["strongs"]} - #{Format.s(entry["word"])} (#{Format.s(entry["transliteration"])})\n" <>
          "#{Format.s(entry["short_definition"])}\n\n"
      end)
  end
end
