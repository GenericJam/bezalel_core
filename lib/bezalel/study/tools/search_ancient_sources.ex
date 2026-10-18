defmodule Bezalel.Study.Tools.SearchAncientSources do
  @moduledoc """
  `search_ancient_sources`: full-text search of the ancient-source corpora
  (ancient pack, FTS5 table `ancient_source_passages_fts`), with corpus,
  period and curated-biblical-link filters.

  Ported from studybible-mcp's `handle_search_ancient_sources`,
  `StudyBibleDB.search_ancient_sources` and `format_ancient_source_results`
  (MIT). Same text, except:

    * a null `corpus` is the default (josephus) and a null `period` none,
      where Python read them as 'none' / no period; arguments are trimmed;
    * `limit` must be a whole number (Python truncated 2.5 to 2);
    * a pack lacking the passages table or the corpus answers with the
      missing-corpus text minus Python's "run upgrade_database.py" advice,
      and the outdated-schema case does not arise (the pack has one schema);
    * a device whose SQLite lacks FTS5 gets an error saying so.

  `result/1` returns the passages as data (citation, corpus, tag, excerpts,
  notes, typed links, provenance). The user's preferences
  (`Bezalel.Study.Preferences`) set the default `limit`, leave out switched-off
  corpora (a search of 'all' covers the rest; with josephus off the default
  corpus is 'all'), and decide the scripture labels and editorial verdicts
  (`Bezalel.Study.Ancient.Passages`).
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Ancient, Args, DB, Preferences, Sources}
  alias Bezalel.Study.Ancient.Passages

  @max_limit 20

  @impl true
  def name, do: "search_ancient_sources"

  @impl true
  def description do
    """
    Find an ancient source passage by searching its words: Jewish texts of the
    Second Temple world to c. AD 200 (Josephus on Herod, the temple, John the
    Baptist and the Jewish revolt; Targum Onkelos; the Qumran rules; Philo;
    1 Enoch and 4 Ezra; the Mishnah). Each result carries a date and edition tag
    (with a canon-status label unless the user turned labels off), and each
    corpus's caveat and the sources are printed once at the end.

    English search is stemmed and matches only the translation's wording. Search
    Greek, Hebrew and Aramaic in their own script (accents, vowel points and case
    are ignored; transliterations such as "logos" do not match). Passages with
    every word come first; otherwise passages with any word, and the output says
    so. Only if nothing matches exactly is a Hebrew or Aramaic word retried
    without prefix letters (ו ב ה ל מ כ ש), and those results are marked.

    Only passage text is searched, not titles or references. `biblical_reference`
    keeps passages with a curated editorial link (aligned, echo, shared tradition;
    contrast when editorial verdicts are on) to that range, never keyword overlap.
    To read a passage by its citation, use lookup_ancient_source.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" =>
            "English or original-language words to search for (e.g. 'John Baptist', 'Herod temple', or 'βαπτισμῷ'). Write Greek, Hebrew, and Aramaic in their own script (accents optional); transliterations do not match. Search operators are ignored."
        },
        "corpus" => %{
          "type" => "string",
          "enum" => Ancient.keys() ++ ["all"],
          "default" => "josephus",
          "description" =>
            "Corpus to search, or 'all'. targum = Onkelos; qumran = CD, 1QS, 1QSa, 1QpHab; pseudepigrapha = 1 Enoch, 4 Ezra; rabbinic = Mishnah. Default: josephus"
        },
        "biblical_reference" => %{
          "type" => "string",
          "description" =>
            "Optional chapter, verse, or verse range (e.g. 'Luke 21', 'Luke 21:5', 'Luke 21:5-6') limiting results to passages with a curated editorial link overlapping it"
        },
        "period" => %{
          "type" => "string",
          "enum" => Ancient.periods(),
          "description" => "Optional editorial period tag"
        },
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => @max_limit,
          "description" =>
            "Maximum passages. Default: the user's setting (8 unless changed), at most #{@max_limit}"
        }
      },
      "required" => ["query"]
    }
  end

  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)), do: {:ok, render(result)}
  end

  @typedoc """
  The search and its filters, then either the passages found (`match`
  `"all"` or `"any"`, `prefix_match` when only prefix-stripped Hebrew
  matched) or `status` `:no_match` / `:no_link` (with the link coverage).
  `prefs` are the preferences it ran under.
  """
  @type t :: %{
          required(:query) => String.t(),
          required(:corpus) => String.t(),
          required(:biblical_reference) => String.t() | nil,
          required(:period) => String.t() | nil,
          required(:terms) => [String.t()],
          required(:prefs) => Preferences.t(),
          required(:status) => :ok | :no_match | :no_link,
          optional(:match) => String.t(),
          optional(:prefix_match) => boolean(),
          optional(:passages) => [Passages.passage()],
          optional(:link_count) => non_neg_integer(),
          optional(:linked_passage_count) => non_neg_integer()
        }

  @doc "The passages matching `args`, under the host's current preferences."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc "The passages matching `args` under `prefs`."
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    query = Args.string(args, "query")

    default =
      if Sources.enabled?(prefs, Sources.ancient("josephus")), do: "josephus", else: "all"

    corpus_arg = args |> Args.optional("corpus") |> Kernel.||(default) |> String.downcase()
    corpus = if corpus_arg == "all", do: nil, else: corpus_arg
    period = Args.optional(args, "period")

    with :ok <- Sources.check_tool(prefs, name()),
         :ok <- check(query, corpus_arg, corpus, period),
         :ok <- if(corpus, do: Sources.check(prefs, Sources.ancient(corpus)), else: :ok),
         {:ok, limit} <- limit(args, prefs) do
      search(query, corpus_arg, corpus, reference(args), period, limit, prefs)
    end
  end

  # The biblical_reference argument, single-chapter citations expanded; nil if none.
  defp reference(args) do
    case Args.reference(args, "biblical_reference") do
      "" -> nil
      reference -> reference
    end
  end

  defp check("", _corpus_arg, _corpus, _period),
    do: {:error, "Please provide words to search in the ancient source text."}

  defp check(_query, corpus_arg, corpus, period) do
    cond do
      corpus && Ancient.corpus(corpus) == nil ->
        {:error,
         "Unsupported ancient-source corpus '#{corpus_arg}'. Available corpora: " <>
           "#{Enum.join(Ancient.keys(), ", ")}, or 'all'."}

      period && period not in periods(corpus) ->
        {:error, "Unsupported period: #{period}. Periods: #{Enum.join(periods(corpus), ", ")}."}

      true ->
        :ok
    end
  end

  defp limit(args, prefs) do
    case Args.integer(args, "limit", Preferences.limit(prefs, @max_limit)) do
      {:ok, limit} when limit in 1..@max_limit//1 -> {:ok, limit}
      _ -> {:error, "'limit' must be an integer from 1 to #{@max_limit}."}
    end
  end

  defp periods(nil), do: Ancient.periods()
  defp periods(corpus), do: Ancient.corpus(corpus).periods

  defp label(nil), do: "ancient-source"
  defp label(corpus), do: Ancient.corpus(corpus).label

  defp search(query, corpus_arg, corpus, reference, period, limit, prefs) do
    terms = Passages.terms(query)
    link_range = reference && Ancient.biblical_range(reference)

    cond do
      terms == [] ->
        {:error,
         "Please provide words to search in the ancient source text. " <>
           "Search operators (AND, OR, NOT, NEAR) are ignored."}

      reference && link_range == nil ->
        {:error,
         "Unsupported biblical_reference '#{reference}'. Use a book " <>
           "name with a chapter, verse, or verse range, e.g. 'Luke 21', " <>
           "'Luke 21:5', or 'Luke 21:5-6'."}

      true ->
        base = %{
          query: query,
          corpus: corpus_arg,
          biblical_reference: reference,
          period: period,
          terms: terms,
          prefs: prefs
        }

        with {:ok, found} <-
               DB.with_pack(:ancient, &find(&1, base, corpus, link_range, limit)),
             do: found
    end
  end

  defp find(conn, base, corpus, link_range, limit) do
    {corpus_condition, corpus_params} = scope(corpus, base.prefs)
    verdicts = Sources.enabled?(base.prefs, "editorial:verdicts")

    present =
      DB.one(
        conn,
        "SELECT 1 FROM ancient_source_passages p WHERE #{corpus_condition} LIMIT 1",
        corpus_params
      )

    cond do
      present == nil ->
        scope =
          if corpus, do: "The #{label(corpus)} corpus is", else: "No ancient-source corpus is"

        {:error,
         "#{scope} not in this device's ancient pack (the ancient_source_passages table is empty)."}

      not fts5?(conn) ->
        {:error,
         "Searching ancient sources needs full-text search (SQLite FTS5), which this " <>
           "device's SQLite build lacks. lookup_ancient_source still reads a passage by " <>
           "its citation (e.g. 'Antiquities 18.116')."}

      not linked?(conn, {corpus_condition, corpus_params}, link_range, verdicts) ->
        {:ok, Map.merge(base, no_link(conn, corpus_condition, corpus_params, verdicts))}

      true ->
        {where, params} =
          filters(corpus_condition, corpus_params, base.period, link_range, verdicts)

        {:ok, stages(conn, base, corpus, where, params, limit)}
    end
  end

  # The corpora searched: the one asked for, or every corpus the user hasn't
  # switched off (at least one is on: `Sources.check_tool/2`).
  defp scope(nil, prefs) do
    all = Ancient.keys()

    case Enum.filter(all, &Sources.enabled?(prefs, Sources.ancient(&1))) do
      ^all -> {"1", []}
      keys -> {"p.corpus IN (#{DB.placeholders(keys)})", keys}
    end
  end

  defp scope(corpus, _prefs), do: {"p.corpus = ?", [corpus]}

  # Has any passage in scope a curated link covering the range?
  defp linked?(_conn, _scope, nil, _verdicts), do: true

  defp linked?(conn, {corpus_condition, corpus_params}, link_range, verdicts) do
    DB.one(
      conn,
      "SELECT 1 FROM ancient_source_passages p WHERE #{corpus_condition} AND " <>
        "#{link_condition(verdicts)} LIMIT 1",
      corpus_params ++ link_params(link_range)
    ) != nil
  end

  defp no_link(conn, corpus_condition, corpus_params, verdicts) do
    coverage =
      DB.one(
        conn,
        """
        SELECT COUNT(*) AS link_count, COUNT(DISTINCT bl.passage_id) AS linked_passage_count
        FROM ancient_source_biblical_links bl
        JOIN ancient_source_passages p ON p.id = bl.passage_id
        WHERE #{corpus_condition}#{if verdicts, do: "", else: " AND bl.relation != 'contrast'"}
        """,
        corpus_params
      )

    %{
      status: :no_link,
      link_count: coverage["link_count"],
      linked_passage_count: coverage["linked_passage_count"]
    }
  end

  # A SQLite built without FTS5 (phones before mob_dev 0.7.29, MOB-487) can't
  # read the table.
  defp fts5?(conn) do
    case Exqlite.Sqlite3.prepare(conn, "SELECT 1 FROM ancient_source_passages_fts LIMIT 0") do
      {:ok, statement} ->
        Exqlite.Sqlite3.release(conn, statement)
        true

      {:error, _} ->
        false
    end
  end

  # A curated link (a "contrast" link only with the editorial verdicts on).
  defp link_condition(verdicts) do
    relation = if verdicts, do: "", else: " AND bl.relation != 'contrast'"

    """
    EXISTS (SELECT 1 FROM ancient_source_biblical_links bl
            WHERE bl.passage_id = p.id AND bl.biblical_book = ?
              AND bl.sort_start <= ? AND bl.sort_end >= ?#{relation})
    """
  end

  defp link_params({book, start, end_}), do: [book, end_, start]

  defp filters(corpus_condition, corpus_params, period, link_range, verdicts) do
    {where, params} = {["ancient_source_passages_fts MATCH ?", corpus_condition], corpus_params}

    {where, params} =
      if period,
        do: {where ++ ["(',' || p.period_tags || ',') LIKE ?"], params ++ ["%,#{period},%"]},
        else: {where, params}

    if link_range,
      do: {where ++ [link_condition(verdicts)], params ++ link_params(link_range)},
      else: {where, params}
  end

  # Every term, then any term; only then, for a Hebrew term, the same with
  # the prefix-stripped variants column.
  defp stages(conn, base, corpus, where, params, limit) do
    exact = "{text original_text_folded}"
    widened = "{text original_text_folded original_prefix_variants}"
    terms = base.terms

    stages =
      [{exact, "all", " AND "}, {exact, "any", " OR "}] ++
        if Enum.any?(terms, &Passages.hebrew?/1),
          do: [{widened, "all", " AND "}, {widened, "any", " OR "}],
          else: []

    found =
      stages
      |> Enum.reject(fn {_, match, _} -> match == "any" and match?([_], terms) end)
      |> Enum.find_value(fn {columns, match, operator} ->
        terms_query = Enum.map_join(terms, operator, &~s("#{&1}"))

        case stage_rows(conn, {where, params, limit}, "#{columns} : (#{terms_query})") do
          [] -> nil
          rows -> {rows, match, columns == widened}
        end
      end)

    case found do
      nil ->
        Map.put(base, :status, :no_match)

      {rows, match, prefix_match} ->
        passages =
          conn
          |> Passages.annotate(rows)
          |> Enum.map(
            &Passages.passage(&1, query: base.query, default_corpus: corpus, prefs: base.prefs)
          )

        Map.merge(base, %{
          status: :ok,
          match: match,
          prefix_match: prefix_match,
          passages: passages
        })
    end
  end

  defp stage_rows(conn, {where, params, limit}, match) do
    DB.all(
      conn,
      """
      SELECT p.*, bm25(ancient_source_passages_fts) AS rank
      FROM ancient_source_passages_fts
      JOIN ancient_source_passages p ON p.id = ancient_source_passages_fts.passage_id
      WHERE #{Enum.join(where, " AND ")}
      ORDER BY rank, p.corpus, p.work_title, p.sort_start
      LIMIT ?
      """,
      [match | params] ++ [limit]
    )
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{status: :no_link} = r) do
    label = label(default_corpus(r))

    "No #{label} passage has an editorial biblical link covering " <>
      "#{r.biblical_reference}. Biblical links are curated narrative " <>
      "overlaps, never inferred from wording; #{r.link_count} " <>
      "links currently cover #{r.linked_passage_count} #{label} " <>
      "passages. Search without biblical_reference to find passages by wording."
  end

  def render(%{status: :no_match} = r) do
    filters =
      if(r.biblical_reference, do: ["biblical_reference=#{r.biblical_reference}"], else: []) ++
        if r.period, do: ["period=#{r.period}"], else: []

    scope = if filters == [], do: "", else: " with filters #{Enum.join(filters, ", ")}"

    "No #{label(default_corpus(r))} passage contains any of the search terms " <>
      "(#{Enum.join(r.terms, ", ")})#{scope}."
  end

  def render(r) do
    filters =
      ["corpus=#{r.corpus}"] ++
        if(r.biblical_reference, do: ["biblical_reference=#{r.biblical_reference}"], else: []) ++
        if r.period, do: ["period=#{r.period}"], else: []

    header =
      ["## Ancient Source Search: #{r.query}", "", "*Filters: #{Enum.join(filters, ", ")}*", ""] ++
        if(r.match == "any",
          do: ["*No passage contains all terms; showing passages matching any term.*", ""],
          else: []
        ) ++
        if r.prefix_match,
          do: [
            "*No exact match: these passages match only after stripping Hebrew/Aramaic prefix " <>
              "letters (ו ב ה ל מ כ ש), which can also match a different word (קדש finds מקדש).*",
            ""
          ],
          else: []

    total = length(r.passages)

    Passages.render(
      header,
      r.passages,
      default_corpus(r),
      r.prefs,
      fn _passage, shown ->
        "*#{total - shown} more results omitted to keep the response short.*"
      end,
      if(r.prefix_match, do: " (prefix match)", else: "")
    )
  end

  defp default_corpus(%{corpus: "all"}), do: nil
  defp default_corpus(%{corpus: corpus}), do: corpus
end
