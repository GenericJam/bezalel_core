defmodule Bezalel.Study.Tools.GetCrossReferences do
  @moduledoc """
  `get_cross_references`: the verses traditionally read alongside a verse,
  strongest first, or a curated chain of passages for a doctrinal theme.

  Ported from studybible-mcp's `handle_get_cross_references` and
  `get_cross_references` (MIT). The core pack's only cross-reference set
  is the Treasury of Scripture Knowledge (Bezalel's build imports TSK
  alone; Harrison/Romhild is not built, Gage/Bradley and Burnett are
  excluded), so the ranking keeps studybible-mcp's TSK tiers and the text
  and description name only the TSK. `result/1` returns the rows. The
  user's preferences (`Bezalel.Study.Preferences`) set the default `limit`
  and can switch off the theme chains (`Bezalel.Study.Sources`,
  `crossrefs:themes`; asking for a theme is then an error).
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{
    Args,
    Citation,
    Citations,
    DB,
    Preferences,
    Reference,
    Sources,
    Translations
  }

  @impl true
  def name, do: "get_cross_references"

  @impl true
  def description do
    """
    Retrieve the cross-references for a Bible reference — the passages traditionally read alongside it — or a curated chain of passages for a doctrinal theme.

    Two modes:

    **By verse reference** (most common). Pass `reference="John 3:16"` (or any
    canonical verse) to get the passages historically read alongside it, from the
    Treasury of Scripture Knowledge (TSK), ranked in three tiers by how many
    commentaries make each link (votes):

      **Tier 3 ("consensus"):** TSK pairs with ≥100 votes — near-universal
        cross-references (top ~0.4% of TSK).
      **Tier 2 ("acknowledged"):** TSK pairs with 20–99 votes — solid topical
        links acknowledged across commentaries (top ~5%).
      **Tier 1 (long-tail):** TSK <20 votes — surface only when explicitly raising
        `limit` for exhaustive study.

    Results typically include the texts the verse quotes, its fulfilment passages,
    and the later authors who picked the verse up.

    **By theme**. Pass `theme="atonement"` (or `salvation_by_grace`, `deity_of_christ`,
    `resurrection`, `holy_spirit`, `justification`) to get a hand-curated chain
    of foundational passages for that doctrine — relevant for broad theological
    questions not anchored to a specific verse.

    **Coverage caveat.** TSK is built on R.A. Torrey's 19th-century
    index, which catalogues **topical/thematic** connections — not necessarily
    direct quotations or verbal allusions. Consequence: a verse with few cross-refs
    here is NOT necessarily a verse with few biblical echoes. Famously,
    Revelation shows surprisingly few links to OT prophetic books even though
    it is saturated with OT symbolism, because Torrey indexed by subject and
    Revelation's subject is "apocalyptic". `find_similar_passages` may surface a
    verbal parallel the topical index misses.

    **Adaptive default — `limit` is a cap, not a target.** The default `limit` is the
    user's setting (8 unless changed). Rows
    are returned in tier-then-strength order, and tier-1 noise (low-vote TSK) is
    suppressed by default whenever the verse has at least 3 rows from tier 2+. So:

      - Signal-rich anchors return up to `limit` strong refs.
      - Signal-poor anchors return only what passes the bar; a short result set
        means the verse has few well-attested links, not that the query failed.

    For the long tail, `source="tsk"` returns all TSK rows including tier 1, and
    `min_strength=0` sets an explicit floor of zero. Either disables tier-1
    suppression; both pair with a higher `limit` (20–30).

    **Interpreting the votes** (full TSK distribution):
        ≥ 500 votes  — extraordinary; near-universal cross-reference (top 0.01%, only 35 pairs)
        100-499      — very strong; the link tradition reflexively makes (top 0.4%)
         50-99       — strong; well-established parallel (top 1.3%)
         20-49       — solid; real connection acknowledged across commentaries (top 5%)
         10-19       — moderate; one of many recognised links (top 12%)
          5-9        — weak; thematic stretch, use with caution (top 33%)
          2-4        — very weak; mostly noise floor (62% of TSK)
          0-1        — noise

    A result whose strongest row has only 5–15 votes indicates a verse the topical
    index does not treat as a major thematic anchor — a materially weaker signal
    than a 200-vote parallel. For such verses `find_similar_passages`
    (verbal/semantic parallels Torrey did not index) covers different ground.\
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
            "Bible reference to find cross-references for (e.g. 'John 3:16', 'Rom 3:23')."
        },
        "theme" => %{
          "type" => "string",
          "description" =>
            "Theological theme. One of: salvation_by_grace, deity_of_christ, atonement, resurrection, holy_spirit, justification."
        },
        "source" => %{
          "type" => "string",
          "enum" => ["tsk"],
          "description" =>
            "'tsk' = Treasury of Scripture Knowledge, the only dataset here; setting it returns the full TSK long tail (no tier-1 suppression)."
        },
        "limit" => %{
          "type" => "integer",
          "description" =>
            "Cap on rows returned (not a target). Default: the user's setting (8 unless changed). The returned count may be smaller when the verse has fewer rows above the noise floor. Values of 20–30 combined with `source='tsk'` or `min_strength=0` return the long tail."
        },
        "min_strength" => %{
          "type" => "integer",
          "description" =>
            "Vote floor for TSK refs. Pairs below this are excluded. Setting this also disables the default tier-1 suppression, since it specifies an explicit floor. Sensible thresholds: 0 (include long-tail), 5 (drops bottom ~75% of TSK), 20 (top ~5% only). Default: tier-1 suppressed when verse is signal-rich."
        }
      }
    }
  end

  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)),
         do: Citations.details(render(result), result, citations(result))
  end

  @typedoc """
  A theme's chain (`theme` set, `rows` with `reference` and `note`) or a
  verse's cross references (`reference` set, `rows` with `target`
  ('Rom.5.8'), `relevance` (TSK votes) and `tier`). `translation` is the
  user's, which the verses (shown by reference, without text) link to;
  `bsb_books` the books it doesn't have, whose verses link to the BSB.
  """
  @type t :: %{
          theme: String.t() | nil,
          reference: String.t() | nil,
          source: String.t() | nil,
          limit: pos_integer(),
          translation: Translations.ref(),
          rows: [DB.row()],
          bsb_books: [String.t()]
        }

  @doc "The cross references (or theme chain) `args` ask for, under the host's current preferences."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc "The cross references (or theme chain) `args` ask for under `prefs`, possibly none."
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    theme = Args.optional(args, "theme")
    reference = Args.reference(args)
    source = Args.optional(args, "source")
    limit = Args.limit(args, Preferences.limit(prefs, nil))
    translation = Translations.get(prefs.translation) || Translations.get("bsb")

    base = %{
      theme: theme,
      reference: nil,
      source: source,
      limit: limit,
      translation: Translations.ref(translation),
      rows: [],
      bsb_books: []
    }

    cond do
      theme ->
        with :ok <- Sources.check(prefs, "crossrefs:themes"),
             {:ok, rows} <- DB.with_pack(:core, &themed(&1, theme)),
             do: with_bsb_books({:ok, %{base | rows: rows}})

      reference == "" ->
        {:error, "Please provide either 'reference' or 'theme'."}

      source not in [nil, "tsk"] ->
        {:error,
         "source must be 'tsk' (the Treasury of Scripture Knowledge, the only " <>
           "cross-reference dataset here) or omitted."}

      true ->
        verse_result(args, base, reference, source, limit)
    end
  end

  defp verse_result(args, base, reference, source, limit) do
    case Args.integer(args, "min_strength", nil) do
      {:ok, min_strength} ->
        with {:ok, rows} <-
               DB.with_pack(:core, &verse(&1, reference, source, limit, min_strength)),
             do: with_bsb_books({:ok, %{base | reference: reference, rows: rows}})

      :error ->
        {:error, "min_strength must be an integer."}
    end
  end

  defp themed(conn, theme) do
    key = theme |> String.downcase() |> String.replace(" ", "_")

    DB.all(conn, "SELECT * FROM thematic_references WHERE theme = ? OR theme LIKE ?", [
      key,
      "%#{key}%"
    ])
  end

  # studybible-mcp's ranking keeps tier 3 for ≥100 votes, tier 2 for 20–99
  # and tier 1 below, ordered by tier, vote bucket, votes and target. With
  # TSK alone (and no pair listed twice) that is votes, then target.
  defp verse(conn, reference, source, limit, min_strength) do
    {floor, floor_params} =
      if min_strength && min_strength > 0,
        do: {" AND relevance >= ?", [min_strength]},
        else: {"", []}

    rows =
      DB.all(
        conn,
        """
        SELECT source, target, relevance,
               CASE WHEN relevance >= 100 THEN 3 WHEN relevance >= 20 THEN 2 ELSE 1 END AS tier
        FROM cross_references
        WHERE source = ? AND type = 'tsk'#{floor}
        ORDER BY relevance DESC, target
        LIMIT ?
        """,
        [Reference.normalize(reference)] ++ floor_params ++ [limit]
      )

    # Tier-1 rows are dropped when the verse has at least 3 rows of tier 2+,
    # unless the caller asked for the long tail (source 'tsk') or set a floor.
    high = Enum.filter(rows, &(&1["tier"] >= 2))

    if source != "tsk" and min_strength == nil and match?([_, _, _ | _], high),
      do: high,
      else: rows
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{theme: theme, rows: []}) when is_binary(theme),
    do: "No cross-references found for theme '#{theme}'."

  def render(%{theme: theme, rows: rows} = result) when is_binary(theme) do
    "## Cross-References: #{theme}\n" <>
      Citation.source_line(chains()) <>
      "\n\n" <>
      Enum.map_join(rows, fn row ->
        "- **#{row["reference"]}**: #{row["note"]}\n" <>
          sub_source(theme_citations(row, result))
      end)
  end

  def render(%{reference: reference, source: source, rows: []}) do
    "No cross-references found for #{reference}." <>
      if(source, do: " (source filter: #{source})", else: "")
  end

  def render(%{reference: reference, limit: limit, rows: [first | _] = rows} = result) do
    "## Cross-References for #{reference}\n\n" <>
      "_#{length(rows)} reference(s) returned (cap limit=#{limit}; " <>
      "actual count may be smaller when verse is signal-poor — by design). " <>
      "TSK = Treasury of Scripture Knowledge._\n" <>
      Citation.source_line(Citations.tsk(first["source"])) <>
      "\n\n" <>
      "### TSK — #{length(rows)}\n" <>
      Enum.map_join(rows, fn row ->
        votes = row["relevance"]
        tag = if votes in [nil, 0], do: "", else: "  *(votes: #{votes})*"

        "- #{Reference.display(row["target"])}#{tag}\n" <>
          sub_source([target_citation(row["target"], result)])
      end) <> "\n"
  end

  @doc """
  The sources `render/1` shows, in its order: for a verse, its cross
  references at OpenBible.info (the TSK) and each target verse in the
  user's translation; for a theme, studybible-mcp's thematic chains and
  each passage in the user's translation.
  """
  @spec citations(t()) :: [Citation.t()]
  def citations(%{rows: []}), do: []

  def citations(%{theme: theme, rows: rows} = result) when is_binary(theme),
    do: [chains() | Enum.flat_map(rows, &theme_citations(&1, result))]

  def citations(%{rows: [first | _] = rows} = result) do
    [
      Citations.tsk(first["source"])
      | Enum.map(rows, &target_citation(&1["target"], result))
    ]
  end

  defp chains, do: Citations.studybible("Thematic chains")

  # A target verse in the user's translation, or the BSB's page for a book
  # that translation doesn't have.
  defp target_citation(target, result),
    do: Citations.scripture(target, link(result, target |> String.split(".") |> hd()))

  defp link(result, book) do
    if book in Map.get(result, :bsb_books, []),
      do: Translations.ref(Translations.get("bsb")),
      else: result.translation
  end

  # A chain's passage ('Romans 3:21-26') at its first verse, labelled as
  # the chain gives it; none for text that isn't a known book's passage.
  defp theme_citations(row, result) do
    with %{book: book, start_chapter: chapter, start_verse: verse} <-
           Reference.parse_passage(row["reference"]),
         name when is_binary(name) <- Reference.book_name(book) do
      citation = Citations.scripture({book, chapter, verse || 1}, link(result, book))
      [%{citation | label: row["reference"]}]
    else
      _ -> []
    end
  end

  # The books of the rows' verses the user's translation doesn't have
  # (`Translations.lacking/2`), whose verses link to the BSB.
  defp with_bsb_books({:ok, %{rows: rows, translation: %{key: key}} = result}) do
    books =
      rows
      |> Enum.map(fn row ->
        case row do
          %{"target" => target} -> target |> String.split(".") |> hd()
          %{"reference" => reference} -> Map.get(Reference.parse_passage(reference) || %{}, :book)
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {:ok, %{result | bsb_books: Translations.lacking(Translations.get(key), books)}}
  end

  defp with_bsb_books(error), do: error

  # A list item's Source line, under it.
  defp sub_source([]), do: ""
  defp sub_source(citations), do: "  " <> Citation.source_line(citations) <> "\n"
end
