defmodule Bezalel.Study.Tools.GetTheologyContext do
  @moduledoc """
  `get_theology_context`: summaries of scholars' work (Heiser, Bradley,
  Owen, Stott, Lennox) on a verse or theme (the notes pack's
  `theology_*` tables).

  Ported from studybible-mcp's `handle_get_theology_context`,
  `has_theology_data`, `get_theology_context_by_reference`,
  `get_theology_context_by_theme`, `get_theology_themes`,
  `_sort_theme_lists`, `format_theology_context` and
  `format_theology_themes` (MIT). Same text, except:

    * an unknown author is an error reading "No scholarship data found for
      author '…'." (their text went on "Run the import script first.");
    * an unknown theme key, and a reference that isn't a verse (or the
      packs' 'Psa.82' form), are errors with their "No theological
      scholarship found" text (for a chapter such as "Psalm 82" their query
      matched nothing; one such as "a.b" raised a Python error);
    * the pack's own absence is the pack error, in place of their
      "Theological scholarship data not available" message.

  A verse's entries are those indexed to it, else those indexed to its
  chapter; theme results alternate between authors.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Reference}
  require Args

  @provenance "*Provenance: these entries are original summaries of the named author's " <>
                "publicly available research and teaching, written for this database. They " <>
                "are not reproduced text from the authors' works. Owen (d. 1683) is in the " <>
                "public domain and is cited by work, with a link to the free text.*"

  @impl true
  def name, do: "get_theology_context"

  @impl true
  def description do
    """
    Get theological scholarship context for a Bible passage or theme.

    Returns scholarly content from multiple authors (Heiser, Bradley, etc.) with verse mappings and theme links. When no author is specified, every scholar's content is searched (theme results alternate between authors), allowing side-by-side comparison.

    Coverage by topic, with the author and theme keys that hold it:
    - The divine council (Psalm 82, Deuteronomy 32, Job 1-2) — Heiser
    - Sons of God / bene elohim (Genesis 6, Job 38) — Heiser
    - The Angel of Yahweh / two-powers theology — Heiser
    - Nephilim, Rephaim, and the giant clans — Heiser
    - The nachash / serpent in Eden (Genesis 3) — Heiser, Bradley
    - Cosmic geography and spiritual warfare — Heiser
    - Deuteronomy 32 worldview / allotment of nations — Heiser, Bradley
    - Salvation, soteriology, the gospel, conversion, atonement — Bradley (theme: domain_transfer)
    - The Fall, Genesis 3, sin entering the world — Bradley (theme: nested_household, corporate_headship)
    - Life/death, light/darkness, righteousness/sin, love/pride and other biblical binary pairs — Bradley (theme: binary_hierarchy)
    - Satan, the devil, spiritual warfare, the enemy, two kingdoms — Bradley (theme: pater_familias_binary)
    - The sin-death connection, wages of sin, power of death — Bradley (theme: sin_death_satan_chain)
    - Corporate solidarity, "in Adam" / "in Christ", federal headship — Bradley (theme: corporate_headship)
    - Satan's imitation of God's kingdom, counterfeit worship — Bradley (theme: rival_counterfeits)
    - Acts 26:17-18 and Paul's commission — Bradley (theme: domain_transfer)
    - Penal substitution, propitiation, definite/particular atonement, imputed righteousness, justification — Owen, Stott (themes: penal_substitution, propitiation, definite_atonement, justification_imputation)
    - Mortification of indwelling sin, sanctification, communion with God, the glory of Christ — Owen (themes: mortification_of_sin, sanctification, communion_with_god, glory_of_christ)
    - Christ's high priesthood, the new covenant, Hebrews — Owen (themes: high_priesthood, new_covenant)
    - The cross of Christ, the four images of salvation, the self-substitution of God — Stott (theme: atonement_models, reconciliation)
    - The Sermon on the Mount, kingdom ethics, the Holy Spirit's fullness (baptism vs filling) — Stott (themes: kingdom_ethics, holy_spirit_work)
    - Genesis 1 and science, creation, the days debate — Lennox (theme: creation_genesis)
    - Providence, God's sovereignty and human freedom, the problem of evil (Joseph, Daniel) — Lennox (themes: providence, divine_sovereignty_freedom)
    - Faithful witness in a hostile culture, Daniel — Lennox (theme: faithful_witness)

    Each entry includes a Source URL when the source is freely available online: Owen's public-domain text (CCEL chapter pages; Monergism volume PDFs for the Exposition of Hebrews), Heiser's papers and Naked Bible podcast transcripts, and Burnett's article series. Stott, Lennox, and Bradley entries have no URL.

    Query by verse reference, theme key, and/or author. For other authors, see
    `list_research_sources`.\
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
            "Bible reference (e.g., 'Psalm 82:1', 'Genesis 6:2', 'Acts 26:18', 'John 8:44')"
        },
        "theme" => %{
          "type" => "string",
          "description" =>
            "Theme key (e.g., 'divine_council', 'pater_familias_binary', 'domain_transfer', " <>
              "'sin_death_satan_chain')"
        },
        "author" => %{
          "type" => "string",
          "description" =>
            "Filter by author: 'heiser', 'bradley', 'owen', 'stott', 'lennox'. " <>
              "Omit to get all scholars' content."
        },
        "limit" => %{
          "type" => "integer",
          "description" => "Maximum entries to return. Default: 4"
        }
      }
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc """
  An entry. `matched_ref` ('Psa.82.6'), `relevance` ("primary",
  "secondary" or "supporting") and `themes` come with a reference query;
  `verse_refs` (the verses it is indexed to) with a theme query.
  """
  @type entry :: %{
          id: integer(),
          title: String.t() | nil,
          chapter_or_episode: String.t() | nil,
          source_author: String.t(),
          source_work: String.t(),
          source_type: String.t(),
          url: String.t() | nil,
          summary: String.t(),
          detail: String.t() | nil,
          matched_ref: String.t() | nil,
          relevance: String.t() | nil,
          themes: [String.t()],
          verse_refs: [String.t()]
        }

  @type theme :: %{
          key: String.t(),
          label: String.t(),
          description: String.t(),
          parent_theme: String.t() | nil,
          entry_count: integer()
        }

  @type t ::
          %{themes: [theme()]}
          | %{
              reference: String.t() | nil,
              theme: String.t() | nil,
              author: String.t() | nil,
              entries: [entry()]
            }

  @doc """
  With neither a reference nor a theme, the themes (those `author` wrote
  on, with an author); else the entries for the theme or, without one, the
  reference (possibly none). An unknown author or theme, or a reference
  that isn't a verse, is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    query = %{
      reference: nonempty(Args.reference(args)),
      theme: Args.optional(args, "theme"),
      author: Args.optional(args, "author")
    }

    limit = Args.limit(args, 4)

    with {:ok, answer} <- DB.with_pack(:notes, &answer(&1, query, limit)), do: answer
  end

  defp answer(conn, query, limit) do
    cond do
      query.author && not author?(conn, query.author) ->
        {:error, "No scholarship data found for author '#{query.author}'."}

      query.theme == nil and query.reference == nil ->
        {:ok, %{themes: themes(conn, query.author)}}

      query.theme ->
        entries(query, theme?(conn, query.theme) && by_theme(conn, query, limit))

      true ->
        entries(query, by_reference(conn, query, limit))
    end
  end

  defp entries(query, entries) when is_list(entries), do: {:ok, Map.put(query, :entries, entries)}
  defp entries(query, _unreadable), do: {:error, not_found(query)}

  defp author?(conn, author),
    do:
      DB.one(conn, "SELECT 1 FROM theology_content WHERE source_author = ? LIMIT 1", [author]) !=
        nil

  defp theme?(conn, theme),
    do: DB.one(conn, "SELECT 1 FROM theology_themes WHERE theme_key = ?", [theme]) != nil

  defp nonempty(""), do: nil
  defp nonempty(text), do: text

  defp themes(conn, nil) do
    conn
    |> DB.all("""
    SELECT tt.*,
           (SELECT COUNT(*) FROM theology_theme_index tti WHERE tti.theme_key = tt.theme_key) AS entry_count
    FROM theology_themes tt
    ORDER BY tt.theme_key
    """)
    |> Enum.map(&theme/1)
  end

  defp themes(conn, author) do
    conn
    |> DB.all(
      """
      SELECT tt.*,
             (SELECT COUNT(*) FROM theology_theme_index tti
              JOIN theology_content tc ON tti.content_id = tc.id
              WHERE tti.theme_key = tt.theme_key AND tc.source_author = ?) AS entry_count
      FROM theology_themes tt
      WHERE EXISTS (
          SELECT 1 FROM theology_theme_index tti
          JOIN theology_content tc ON tti.content_id = tc.id
          WHERE tti.theme_key = tt.theme_key AND tc.source_author = ?
      )
      ORDER BY tt.theme_key
      """,
      [author, author]
    )
    |> Enum.map(&theme/1)
  end

  defp theme(row) do
    %{
      key: row["theme_key"],
      label: row["theme_label"],
      description: row["description"],
      parent_theme: row["parent_theme"],
      entry_count: row["entry_count"]
    }
  end

  # Entries alternate between authors (each author's in id order), so a
  # small limit still shows every scholar's view of the theme.
  defp by_theme(conn, query, limit) do
    {author_filter, author_params} = author_filter(query.author)

    conn
    |> DB.all(
      """
      SELECT * FROM (
          SELECT tc.*, tt.theme_label, tt.description AS theme_description,
                 GROUP_CONCAT(DISTINCT vi.reference) AS verse_refs
          FROM theology_content tc
          JOIN theology_theme_index tti ON tc.id = tti.content_id
          JOIN theology_themes tt ON tti.theme_key = tt.theme_key
          LEFT JOIN theology_verse_index vi ON tc.id = vi.content_id
          WHERE tti.theme_key = ?#{author_filter}
          GROUP BY tc.id
      )
      ORDER BY ROW_NUMBER() OVER (PARTITION BY source_author ORDER BY id),
               source_author, id
      LIMIT ?
      """,
      [query.theme] ++ author_params ++ [limit]
    )
    |> Enum.map(&entry/1)
  end

  # Each entry ranked by its best match: primary before secondary or
  # supporting, then by verse, then by id. Entries indexed to the verse,
  # else to its chapter.
  @best_match "MIN(CASE vi.relevance WHEN 'primary' THEN 0 ELSE 1 END * 1000" <>
                " + COALESCE(vi.verse, 0)) AS match_rank"

  defp by_reference(conn, query, limit) do
    normalized = Reference.normalize(query.reference)

    with [book | rest] when rest != [] <- String.split(normalized, "."),
         {:ok, chapter} <- chapter(hd(rest)) do
      {author_filter, author_params} = author_filter(query.author)

      select = fn where, params ->
        conn
        |> DB.all(
          """
          SELECT tc.*, vi.reference AS matched_ref, vi.relevance, #{@best_match},
                 GROUP_CONCAT(DISTINCT tt.theme_key) AS themes
          FROM theology_content tc
          JOIN theology_verse_index vi ON tc.id = vi.content_id
          LEFT JOIN theology_theme_index tti ON tc.id = tti.content_id
          LEFT JOIN theology_themes tt ON tti.theme_key = tt.theme_key
          WHERE #{where}#{author_filter}
          GROUP BY tc.id
          ORDER BY match_rank, tc.id
          LIMIT ?
          """,
          params ++ author_params ++ [limit]
        )
        |> Enum.map(&entry/1)
      end

      {chapter_where, chapter_params} =
        if chapter in [nil, 0],
          do: {"vi.book = ?", [book]},
          else: {"vi.book = ? AND vi.chapter = ?", [book, chapter]}

      case select.("vi.reference = ?", [normalized]) do
        [] -> select.(chapter_where, chapter_params)
        entries -> entries
      end
    else
      _ -> :error
    end
  end

  defp chapter(text) do
    case Integer.parse(String.trim(text)) do
      {n, ""} when Args.is_sqlite_integer(n) -> {:ok, n}
      _ -> :error
    end
  end

  defp author_filter(nil), do: {"", []}
  defp author_filter(author), do: {" AND tc.source_author = ?", [author]}

  defp entry(row) do
    %{
      id: row["id"],
      title: row["title"],
      chapter_or_episode: row["chapter_or_episode"],
      source_author: row["source_author"],
      source_work: row["source_work"],
      source_type: row["source_type"],
      url: row["url"],
      summary: row["content_summary"],
      detail: row["content_detail"],
      matched_ref: row["matched_ref"],
      relevance: row["relevance"],
      # GROUP_CONCAT has no defined order.
      themes: split(row["themes"]) |> Enum.sort(),
      verse_refs: split(row["verse_refs"])
    }
  end

  defp split(value) when value in [nil, ""], do: []
  defp split(value), do: String.split(value, ",")

  defp not_found(query) do
    description =
      if query.theme, do: "theme='#{query.theme}'", else: "reference='#{query.reference}'"

    author = if query.author, do: " (author='#{query.author}')", else: ""
    "No theological scholarship found for #{description}#{author}."
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{themes: themes}) do
    lines =
      Enum.flat_map(themes, fn theme ->
        parent =
          if Format.present?(theme.parent_theme),
            do: ["**Parent theme**: #{theme.parent_theme}"],
            else: []

        ["### #{theme.label} (`#{theme.key}`)", Format.s(theme.description)] ++
          parent ++ ["**Entries**: #{theme.entry_count}", ""]
      end)

    Enum.join(["## Theological Themes\n" | lines], "\n")
  end

  def render(%{entries: []} = result), do: not_found(result)

  def render(%{entries: entries} = result) do
    label = if result.author, do: String.capitalize(result.author), else: "Theological"

    header =
      "## #{label} Scholarship Context" <>
        if(result.reference, do: " for #{result.reference}", else: "") <>
        if(result.theme, do: " — theme: #{result.theme}", else: "")

    lines = Enum.flat_map(entries, &entry_lines/1) ++ [@provenance, ""]
    header <> "\n\n" <> Enum.join(lines, "\n")
  end

  defp entry_lines(entry) do
    author = Format.s(entry.source_author)
    work = Format.s(entry.source_work)

    source =
      if author != "" and String.starts_with?(String.downcase(work), String.downcase(author)),
        do: "*#{work}*",
        else: "#{author} — *#{work}*"

    source =
      if Format.present?(entry.source_type), do: "#{source} (#{entry.source_type})", else: source

    heading =
      if Format.present?(entry.title), do: entry.title, else: Format.s(entry.chapter_or_episode)

    ["### #{heading}", "**Source**: #{source}"] ++
      field("**Source URL**", entry.url) ++
      field("**Chapter/Episode**", entry.chapter_or_episode) ++
      field("**Matched Reference**", entry.matched_ref) ++
      field("**Themes**", Enum.join(entry.themes, ",")) ++
      [""] ++
      if(Format.present?(entry.summary), do: [entry.summary, ""], else: []) ++
      if(Format.present?(entry.detail),
        do: ["**Detail**:", Format.truncate(entry.detail, 2000), ""],
        else: []
      ) ++
      ["---", ""]
  end

  defp field(label, value),
    do: if(Format.present?(value), do: ["#{label}: #{value}"], else: [])
end
