defmodule Bezalel.Study.Tools.SearchByStrongs do
  @moduledoc """
  `search_by_strongs`: the verses where a Greek or Hebrew word (by Strong's
  number) appears.

  Ported from studybible-mcp's `handle_search_by_strongs` (MIT); same
  text. `result/1` returns the lexicon row and the verses.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Lexicon, Verses}

  @default_limit 4

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
          "description" => "Maximum verses to return. Default: #{@default_limit}"
        }
      },
      "required" => ["strongs"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc "`strongs` as given, its lexicon entry, and the verses that carry it."
  @type t :: %{strongs: String.t(), entry: DB.row(), verses: [Format.verse_view()]}

  @doc "The verses with `args`' Strong's number; an unknown number is an error."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    case Args.string(args, "strongs") do
      "" ->
        {:error, "Please provide a Strong's number (e.g., 'G26' or 'H3068')."}

      strongs ->
        limit = Args.limit(args, @default_limit)

        case DB.with_pack(:core, &search(&1, strongs, limit)) do
          {:ok, nil} -> {:error, "Unknown Strong's number: #{strongs}"}
          {:ok, result} -> {:ok, result}
          error -> error
        end
    end
  end

  defp search(conn, strongs, limit) do
    if entry = Lexicon.entry(conn, strongs) do
      verses = conn |> Verses.with_strongs(strongs, limit) |> Enum.map(&Format.verse_view/1)
      %{strongs: strongs, entry: entry, verses: verses}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{strongs: strongs, entry: entry, verses: verses}) do
    bsb = Format.bsb_label(verses)

    body =
      if verses == [],
        do: "No verses found with this Strong's number in the database.\n",
        else: Enum.map_join(verses, &"**#{&1.reference}**: #{&1.english}\n\n")

    "## Verses with #{strongs} (#{Format.s(entry["word"])} - #{Format.s(entry["transliteration"])})#{bsb}\n\n" <>
      "*#{Format.s(entry["short_definition"])}*\n\n" <> body
  end
end
