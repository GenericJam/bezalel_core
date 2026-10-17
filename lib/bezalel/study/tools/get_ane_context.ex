defmodule Bezalel.Study.Tools.GetAneContext do
  @moduledoc """
  `get_ane_context`: Ancient Near East background for a passage, a
  dimension or a period (the notes pack's `ane_entries`).

  Ported from studybible-mcp's `handle_get_ane_context`,
  `_parse_key_ref_books_chapters`, `_refine_broad_entries` (`server.py`),
  `get_ane_dimensions`, `get_ane_context` (`database.py`),
  `format_ane_context`, `format_ane_dimensions` and the period labels of
  `parsers/ane_context.py` (MIT). Same text. A reference that doesn't
  parse, or a dimension or period outside the schema's lists, is an error
  with their "No ANE context entries found" text; the pack's own absence
  is the pack error, in place of their "ANE context data not available"
  message. `result/1` returns the entries with their list fields decoded.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Patterns, Reference}
  require Args

  @dimensions ~w(cosmology_worldview religious_practices social_structure legal_covenant
                 political_imperial economic_life literary_conventions warfare_military
                 daily_life_material_culture death_afterlife gender_family education_literacy
                 ane_methodology)

  @periods [
    {"patriarchal", "Patriarchal Period (c. 2000-1550 BC)"},
    {"exodus_conquest", "Exodus & Conquest (c. 1550-1200 BC)"},
    {"judges_early_monarchy", "Judges & Early Monarchy (c. 1200-1000 BC)"},
    {"united_monarchy", "United Monarchy (c. 1000-930 BC)"},
    {"divided_monarchy", "Divided Monarchy (c. 930-722 BC)"},
    {"assyrian_babylonian", "Assyrian & Babylonian Period (c. 722-539 BC)"},
    {"persian", "Persian Period (c. 539-332 BC)"},
    {"hellenistic", "Hellenistic Period (c. 332-63 BC)"},
    {"roman", "Roman Period (c. 63 BC-AD 100)"}
  ]
  @period_keys Enum.map(@periods, &elem(&1, 0))

  # At most this many entries (before broad entries are refined).
  @limit 30

  @impl true
  def name, do: "get_ane_context"

  @impl true
  def description do
    """
    Get Ancient Near East (ANE) cultural and historical background for a biblical passage.

    The biblical authors and their audiences lived in the Ancient Near East with fundamentally
    different assumptions about cosmology, social structure, religion, law, and daily life.
    This tool retrieves structured ANE contextual data on what the text meant
    to its original audience.

    Relevant to passages involving:
    - Creation, flood, or cosmological texts (three-tier universe, cosmic waters)
    - Encountering divine council, heavenly assembly, or "sons of God" language
    - Reading about the serpent, Eden, the fall, or spiritual warfare passages
    - Encountering references to temples, sacrifices, or religious practices
    - Studying meal, table, or eating passages (fellowship, allegiance, covenant meals)
    - Encountering household, family, or father language applied to God
    - Reading about covenants, treaties, or legal codes (suzerainty treaties, lex talionis)
    - Studying honor/shame dynamics in Gospels or Epistles
    - Understanding marriage customs, family structures, or inheritance laws
    - Reading about warfare, kingship, or imperial contexts
    - Studying Levitical purity, clean/unclean categories, or scapegoat rituals
    - Encountering literary forms (chiasm, inclusio, lament, oracle)
    - Needing background on daily life, agriculture, or material culture
    - Encountering "soul," "spirit," nephesh, or ruach language (Hebrew vs. Greek anthropology)
    - Any passage where modern Western assumptions might obscure the ANE meaning
    - Needing the interpretive methodology (derivation hierarchy, confidence calibration)

    13 dimensions: cosmology_worldview, religious_practices, social_structure, legal_covenant,
    political_imperial, economic_life, literary_conventions, warfare_military,
    daily_life_material_culture, death_afterlife, gender_family, education_literacy,
    ane_methodology

    9 periods: patriarchal, exodus_conquest, judges_early_monarchy, united_monarchy,
    divided_monarchy, assyrian_babylonian, persian, hellenistic, roman

    With no arguments, returns the available dimensions and periods. With a
    reference alone, returns all ANE context matching that passage. The dimension
    and period parameters narrow the result set. The dimension 'ane_methodology'
    returns the derivation hierarchy, confidence calibration, and methodological
    limits that apply to ANE parallels generally.\
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
            "Bible reference (e.g., 'Genesis 1:1', 'Deuteronomy 5:1', 'Matthew 5:1')"
        },
        "dimension" => %{
          "type" => "string",
          "description" =>
            "ANE dimension to filter by (e.g., 'cosmology_worldview', 'legal_covenant')",
          "enum" => @dimensions
        },
        "period" => %{
          "type" => "string",
          "description" => "Historical period to filter by",
          "enum" => @period_keys
        },
        "detail_level" => %{
          "type" => "string",
          "description" =>
            "Output detail level. 'brief' = title + summary + significance for all entries. " <>
              "'standard' (default) = full detail for direct chapter matches, brief for " <>
              "broad/whole-book matches. 'full' = full detail for all entries.",
          "enum" => ["brief", "standard", "full"],
          "default" => "standard"
        }
      }
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc """
  An entry: its id, dimension, title and texts, with `match_type` "direct"
  (mapped to the passage's chapter) or "broad" (to the whole book) for a
  reference query, else nil.
  """
  @type entry :: %{
          id: String.t(),
          dimension: String.t(),
          dimension_label: String.t(),
          title: String.t(),
          summary: String.t(),
          detail: String.t() | nil,
          ane_parallels: [String.t()],
          interpretive_significance: String.t() | nil,
          period: String.t() | nil,
          period_label: String.t() | nil,
          key_references: [String.t()],
          scholarly_sources: [String.t()],
          match_type: String.t() | nil
        }

  @type t ::
          %{dimensions: [%{dimension: String.t(), label: String.t(), entry_count: integer()}]}
          | %{
              reference: String.t() | nil,
              dimension: String.t() | nil,
              period: String.t() | nil,
              detail_level: String.t(),
              entries: [entry()]
            }

  @doc """
  With no reference, dimension or period, the dimensions with their entry
  counts; else the entries matching them (possibly none). A reference that
  doesn't parse, or an unknown dimension or period, is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    query = %{
      reference: nonempty(Args.reference(args)),
      dimension: Args.optional(args, "dimension"),
      period: Args.optional(args, "period")
    }

    passage = query.reference && Reference.parse_passage(query.reference)

    cond do
      query == %{reference: nil, dimension: nil, period: nil} ->
        dimensions()

      not readable?(query, passage) ->
        {:error, not_found(query)}

      true ->
        detail_level = Args.optional(args, "detail_level") || "standard"

        with {:ok, rows} <- DB.with_pack(:notes, &entries(&1, query, passage)) do
          entries = rows |> refine(passage) |> Enum.map(&entry/1)
          {:ok, Map.merge(query, %{detail_level: detail_level, entries: entries})}
        end
    end
  end

  defp nonempty(""), do: nil
  defp nonempty(text), do: text

  # A reference that parses to a chapter SQLite can bind, and a dimension and
  # period from the schema's lists.
  defp readable?(query, passage) do
    (query.reference == nil or (passage != nil and Args.is_sqlite_integer(passage.start_chapter))) and
      (query.dimension == nil or query.dimension in @dimensions) and
      (query.period == nil or query.period in @period_keys)
  end

  defp dimensions do
    sql = """
    SELECT dimension, dimension_label, COUNT(*) AS entry_count
    FROM ane_entries
    GROUP BY dimension, dimension_label
    ORDER BY dimension
    """

    with {:ok, rows} <- DB.with_pack(:notes, &DB.all(&1, sql)) do
      {:ok,
       %{
         dimensions:
           Enum.map(
             rows,
             &%{
               dimension: &1["dimension"],
               label: &1["dimension_label"],
               entry_count: &1["entry_count"]
             }
           )
       }}
    end
  end

  defp entries(conn, query, passage) do
    {join, conditions, params, extra, order} =
      if passage do
        {" JOIN ane_book_mappings bm ON e.id = bm.entry_id",
         [
           "bm.book = ?",
           "(bm.chapter_start IS NULL OR (bm.chapter_start <= ? AND " <>
             "(bm.chapter_end IS NULL OR bm.chapter_end >= ?)))"
         ], [passage.book, passage.start_chapter, passage.start_chapter],
         """
         ,
             CASE
                 WHEN bm.chapter_start IS NULL THEN 1000
                 ELSE (COALESCE(bm.chapter_end, bm.chapter_start) - bm.chapter_start + 1)
             END AS relevance_score,
             CASE WHEN bm.chapter_start IS NOT NULL THEN 'direct' ELSE 'broad' END AS match_type\
         """, "ORDER BY relevance_score, e.dimension, e.period"}
      else
        {"", [], [], "", "ORDER BY e.dimension, e.period"}
      end

    {conditions, params} =
      Enum.reduce(
        [{"e.dimension = ?", query.dimension}, {"e.period = ?", query.period}],
        {conditions, params},
        fn
          {_condition, nil}, acc ->
            acc

          {condition, value}, {conditions, params} ->
            {conditions ++ [condition], params ++ [value]}
        end
      )

    where = if conditions == [], do: "", else: " WHERE " <> Enum.join(conditions, " AND ")

    sql = """
    SELECT DISTINCT e.*#{extra}
    FROM ane_entries e#{join}#{where}
    #{order}
    LIMIT ?
    """

    DB.all(conn, sql, params ++ [@limit])
  end

  # A whole-book ("broad") entry whose key references cite the passage's
  # chapter is promoted to direct; one whose key references never cite the
  # book is dropped; one with no readable key references is kept.
  defp refine(rows, nil), do: rows

  defp refine(rows, %{book: book, start_chapter: chapter}) do
    Enum.flat_map(rows, fn row ->
      cited = key_chapters(row["key_references"])

      cond do
        row["match_type"] != "broad" or MapSet.size(cited) == 0 -> [row]
        MapSet.member?(cited, {book, chapter}) -> [%{row | "match_type" => "direct"}]
        Enum.any?(cited, fn {cited_book, _} -> cited_book == book end) -> [row]
        true -> []
      end
    end)
  end

  @doc """
  The `{book code, chapter}` each key reference starts in ("1 Cor 12:12-27"
  is `{"1Co", 12}`); references that don't start with a book and chapter
  are skipped.
  """
  @spec key_chapters(String.t() | [String.t()] | nil) :: MapSet.t({String.t(), integer()})
  def key_chapters(key_references) do
    for reference <- Format.json(key_references, []) || [],
        is_binary(reference),
        [_, book, chapter] <- [
          Regex.run(Patterns.get(:ane_key_reference), String.trim(reference))
        ],
        into: MapSet.new() do
      {Reference.abbreviation(book), String.to_integer(chapter)}
    end
  end

  defp entry(row) do
    %{
      id: row["id"],
      dimension: row["dimension"],
      dimension_label: row["dimension_label"],
      title: row["title"],
      summary: row["summary"],
      detail: row["detail"],
      ane_parallels: list(row["ane_parallels"]),
      interpretive_significance: row["interpretive_significance"],
      period: row["period"],
      period_label: row["period_label"],
      key_references: list(row["key_references"]),
      scholarly_sources: list(row["scholarly_sources"]),
      match_type: row["match_type"]
    }
  end

  defp list(value) do
    case Format.json(value, []) do
      items when is_list(items) -> items
      _ -> []
    end
  end

  defp not_found(query) do
    parts =
      for {key, value} <- [
            reference: query.reference,
            dimension: query.dimension,
            period: query.period
          ],
          value,
          do: "#{key}=#{value}"

    "No ANE context entries found for #{Enum.join(parts, ", ")}."
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{dimensions: dimensions}) do
    Enum.join(
      [
        "## Ancient Near East Context — Available Dimensions",
        "",
        "Use `get_ane_context` with a `reference` to get relevant ANE background for any passage.",
        "Optionally filter by `dimension` and/or `period`.",
        "",
        "### Dimensions",
        ""
      ] ++
        Enum.map(dimensions, &"- **#{&1.label}** (`#{&1.dimension}`) — #{&1.entry_count} entries") ++
        ["", "### Periods", ""] ++
        Enum.map(@periods, fn {key, label} -> "- `#{key}` — #{label}" end) ++
        [""],
      "\n"
    )
  end

  def render(%{entries: []} = result), do: not_found(result)

  def render(%{entries: entries, reference: reference, detail_level: level}) do
    header = "## Ancient Near East Context" <> if(reference, do: " for #{reference}", else: "")
    header <> "\n\n" <> Enum.join(body(entries, level), "\n")
  end

  defp body(entries, level) do
    has_match_types = Enum.any?(entries, &Format.present?(&1.match_type))

    cond do
      level == "full" or not has_match_types ->
        grouped(entries, if(level == "brief", do: &brief/1, else: &full/1))

      level == "brief" ->
        grouped(entries, &brief/1)

      true ->
        direct = Enum.filter(entries, &(&1.match_type == "direct"))
        broad = Enum.filter(entries, &(&1.match_type == "broad"))

        direct_lines =
          if direct == [],
            do: [],
            else: ["# Directly Relevant to This Passage", "" | grouped(direct, &full/1)]

        broad_lines =
          if broad == [],
            do: [],
            else: [
              "# General ANE Reading Frame",
              "*These entries provide broad cultural context for this book. Summaries shown; " <>
                "call with detail_level='full' for complete entries.*",
              "" | grouped(broad, &brief/1)
            ]

        direct_lines ++ broad_lines
    end
  end

  # Entries under their dimension, in first-seen order.
  defp grouped(entries, formatter) do
    {labels, groups} =
      Enum.reduce(entries, {[], %{}}, fn entry, {labels, groups} ->
        label = entry.dimension_label
        labels = if Map.has_key?(groups, label), do: labels, else: [label | labels]
        {labels, Map.update(groups, label, [entry], &[entry | &1])}
      end)

    labels
    |> Enum.reverse()
    |> Enum.flat_map(fn label ->
      ["## #{label}", ""] ++
        Enum.flat_map(Enum.reverse(groups[label]), formatter) ++ ["---", ""]
    end)
  end

  defp full(entry) do
    period =
      if Format.present?(entry.period_label), do: ["*Period: #{entry.period_label}*"], else: []

    ["### #{entry.title}"] ++
      period ++
      [""] ++
      paragraph(entry.summary) ++
      paragraph(entry.detail) ++
      if(entry.ane_parallels == [],
        do: [],
        else: ["**ANE Parallels:**" | Enum.map(entry.ane_parallels, &"- #{&1}")] ++ [""]
      ) ++
      significance(entry) ++
      key_references(entry) ++
      if(entry.scholarly_sources == [],
        do: [],
        else: ["**Sources:** #{Enum.join(entry.scholarly_sources, "; ")}", ""]
      )
  end

  defp brief(entry) do
    ["### #{entry.title}", ""] ++
      paragraph(entry.summary) ++ significance(entry) ++ key_references(entry)
  end

  defp paragraph(text), do: if(Format.present?(text), do: [text, ""], else: [])

  defp significance(entry) do
    if Format.present?(entry.interpretive_significance),
      do: ["**Interpretive Significance:** #{entry.interpretive_significance}", ""],
      else: []
  end

  defp key_references(%{key_references: []}), do: []

  defp key_references(%{key_references: refs}),
    do: ["**Key References:** #{Enum.join(refs, ", ")}", ""]
end
