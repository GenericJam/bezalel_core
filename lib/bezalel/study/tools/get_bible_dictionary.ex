defmodule Bezalel.Study.Tools.GetBibleDictionary do
  @moduledoc """
  `get_bible_dictionary`: Tyndale Bible Dictionary articles on a topic (the
  notes pack's BibleAquifer content).

  Ported from studybible-mcp's `handle_get_bible_dictionary`,
  `get_bible_dictionary` and `format_dictionary_article` (MIT). Same text;
  the pack's own absence is the pack error, in place of their "Aquifer data
  not available" message. `result/1` returns the articles untruncated.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Aquifer, Args}

  @impl true
  def name, do: "get_bible_dictionary"

  @impl true
  def description do
    """
    Look up a topic in the Tyndale Bible Dictionary.

    Contains 500+ topical articles covering:
    - Biblical people and places
    - Theological concepts and doctrines
    - Cultural practices and customs
    - Historical background
    - Archaeological findings

    Relevant for background on a biblical topic, historical or cultural context, a
    detailed article on a person, place, or concept, or a published definition of a
    theological term.

    Returns the full dictionary article with cross-references.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "topic" => %{
          "type" => "string",
          "description" =>
            "Topic to look up (e.g., 'Abraham', 'covenant', 'baptism', 'Pharisees')"
        }
      },
      "required" => ["topic"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @type t :: %{topic: String.t(), articles: [Aquifer.article()]}

  @doc "The articles on `args`' topic (possibly none); no topic is an error."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    case Args.string(args, "topic") do
      "" ->
        {:error, "Please provide a topic to look up."}

      topic ->
        with {:ok, articles} <- Aquifer.search("dictionary", topic),
             do: {:ok, %{topic: topic, articles: articles}}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{topic: topic, articles: []}), do: "No dictionary article found for '#{topic}'."

  def render(%{articles: articles}) do
    Aquifer.render(
      articles,
      4000,
      "\n\n*[Article truncated — full text available in the Tyndale Bible Dictionary]*"
    )
  end
end
