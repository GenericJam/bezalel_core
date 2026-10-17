defmodule Bezalel.Study.Tools.FindSimilarPassages do
  @moduledoc """
  `find_similar_passages`: the passages nearest a verse in meaning.

  Ported from studybible-mcp's `handle_find_similar_passages` and
  `find_similar_passages` (MIT). Where those searched sqlite-vec tables of
  OpenAI vectors at call time, this reads the 20 nearest passages per verse
  that the pack build precomputed (`similar_passages`, BGE-small vectors of
  the BSB; data/README.md), so it needs no vector extension and returns at
  most 20. The similarity printed is the stored cosine similarity, and the
  text is the same as theirs. `result/1` returns the source verse and the
  passages with their preview verses.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Hermeneutics, Verses}

  @default_limit 4
  # Verses fetched for a passage's preview: ample for the 500 characters shown.
  @preview_verses 30

  @impl true
  def name, do: "find_similar_passages"

  @impl true
  def description do
    """
    Find passages with similar semantic content to a given Bible verse.

    Takes a verse reference and returns semantically similar passages ranked by
    similarity score (at most 20). Matching is by vector embedding of the English
    text rather than shared vocabulary, so it surfaces connections that explicit
    cross-reference indexes and word searches miss.

    Typical results:
    - Psalm 22:18 (lots cast for clothing) → John 19:24, Matthew 27:35 (the crucifixion)
    - Deuteronomy 6:5 (love the LORD with all your heart) → Mark 12:30, Matthew 22:37
    - Isaiah 53:5 (by his wounds) → 1 Peter 2:24
    - Proverbs wisdom themes → James practical wisdom

    **What the similarity score does and does not mean.** The score measures
    proximity in embedding space, which is not evidence of a theological or
    authorial connection. Two passages can share vocabulary and imagery while
    differing in genre, historical setting, referent, and authorial intent. The
    returned set mixes several distinct phenomena that the score cannot tell apart:
    direct quotation (an explicit OT citation in the NT), deliberate allusion,
    shared tradition (common Jewish or Christian concepts), and coincidental
    verbal overlap between unrelated texts.

    Establishing which of these applies to a given pair requires the passages'
    genre, historical setting, and literary context — `lookup_verse` returns genre
    background, `get_study_notes` and `get_ane_context` cover context and original
    audience, and `get_cross_references` indicates whether the link is attested in
    the cross-reference tradition.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "reference" => %{
          "type" => "string",
          "description" =>
            "Bible reference to find similar passages for (e.g., 'John 3:16', 'Daniel 7:13')"
        },
        "limit" => %{
          "type" => "integer",
          "description" =>
            "Number of similar passages to return (at most 20). Default: #{@default_limit}"
        }
      },
      "required" => ["reference"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc """
  A similar passage: its reference ('Jhn.19.23 - Jhn.19.24'), first verse,
  similarity (0–1, and the stored permille), verse count and preview verses.
  """
  @type passage :: %{
          reference: String.t(),
          reference_start: String.t(),
          similarity: float(),
          permille: non_neg_integer(),
          verse_count: pos_integer(),
          preview: [Format.verse_view()]
        }

  @typedoc "The source verse (nil when not in the pack) and its similar passages."
  @type t :: %{
          reference: String.t(),
          source: Format.verse_view() | nil,
          passages: [passage()]
        }

  @doc "The passages similar to `args`' verse (none when the verse isn't in the pack)."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    case Args.reference(args) do
      "" ->
        {:error, "Please provide a verse reference (e.g., 'John 3:16')."}

      reference ->
        limit = Args.limit(args, @default_limit)
        DB.with_pack(:core, &similar(&1, reference, limit))
    end
  end

  defp similar(conn, reference, limit) do
    case Verses.get(conn, reference) do
      nil ->
        %{reference: reference, source: nil, passages: []}

      verse ->
        passages =
          conn
          |> DB.all(
            """
            SELECT p.reference_start, p.reference_end, p.start_verse_id, p.end_verse_id,
                   p.verse_count, s.similarity_permille
            FROM similar_passages s JOIN passages p ON p.id = s.passage_id
            WHERE s.verse_id = ?
            ORDER BY s.rank
            LIMIT ?
            """,
            [verse["id"], limit]
          )
          |> Enum.map(&passage(conn, &1))

        %{reference: reference, source: Format.verse_view(verse), passages: passages}
    end
  end

  defp passage(conn, row) do
    %{
      reference:
        if(row["reference_start"] == row["reference_end"],
          do: row["reference_start"],
          else: "#{row["reference_start"]} - #{row["reference_end"]}"
        ),
      reference_start: row["reference_start"],
      similarity: row["similarity_permille"] / 1000,
      permille: row["similarity_permille"],
      verse_count: row["verse_count"],
      preview:
        conn
        |> Verses.span(row["start_verse_id"], row["end_verse_id"], @preview_verses)
        |> Enum.map(&Format.verse_view/1)
    }
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{reference: reference, passages: []}) do
    "No similar passages found for #{reference}. The verse may not be in the database."
  end

  def render(%{reference: reference, source: source, passages: passages}) do
    shown = [source | Enum.flat_map(passages, & &1.preview)]
    bsb = Format.bsb_label(shown)
    source_genre = Hermeneutics.genre_from_reference(reference)

    "## Passages Similar to #{reference}#{bsb}\n\n" <>
      "**Source**: #{source.english}\n\n" <>
      "---\n\n" <>
      "⚠️ **Hermeneutical Caution**: Semantic similarity indicates shared vocabulary " <>
      "and concepts, but does NOT establish theological connection. Before using any " <>
      "passage below, verify:\n" <>
      "1. Genre compatibility with the source passage\n" <>
      "2. Whether the author intended an allusion/quotation\n" <>
      "3. Historical and literary context of each passage\n" <>
      "4. What each text meant to its original audience\n\n" <>
      "---\n\n" <>
      (passages
       |> Enum.with_index(1)
       |> Enum.map_join(fn {passage, rank} -> passage_text(passage, rank, source_genre) end))
  end

  defp passage_text(passage, rank, source_genre) do
    genre = Hermeneutics.genre_from_reference(passage.reference_start)
    percent = :erlang.float_to_binary(passage.permille / 10, decimals: 1)

    genre_line =
      if genre && source_genre && genre != source_genre,
        do: "⚡ **Genre**: #{genre} (source is #{source_genre})\n\n",
        else: ""

    text =
      passage.preview
      |> Enum.map_join(" ", & &1.english)
      |> Format.truncate(500, "...")

    count =
      if passage.verse_count > 1,
        do: "*(#{passage.verse_count} verses in this passage)*\n\n",
        else: ""

    "### #{rank}. #{passage.reference} (#{percent}% similar)\n\n" <>
      genre_line <> "#{text}\n\n" <> count
  end
end
