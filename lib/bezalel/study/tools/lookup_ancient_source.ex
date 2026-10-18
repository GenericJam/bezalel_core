defmodule Bezalel.Study.Tools.LookupAncientSource do
  @moduledoc """
  `lookup_ancient_source`: an ancient source by citation ('Antiquities
  18.116', 'CD 6:11', 'm. Sukkah 4:9', '4Q174 1–2 i 10'), the passages of
  the work's pack (ancient, or scrolls for the Qumran manuscripts of
  `Bezalel.Study.Ancient.Scrolls`) overlapping it, in citation order. No
  full-text search, so it works on a device whose SQLite lacks FTS5.

  A scrolls-pack manuscript is cited by fragment or column label and line
  (`Ancient.parse_fragment/1`); the label is looked up in the pack
  (`section_number`, the label's `Ancient.fragment_key/1`; `book_number`,
  its position in the manuscript) to give the sort range, so 'frg. 1–2 i'
  and 'f1_2i', '11QMelch ii 18' and '11Q13 2:18' cite the same lines. An
  unknown label lists the manuscript's labels; without the scrolls pack the
  citation is the missing-pack error.

  Ported from studybible-mcp's `handle_lookup_ancient_source`,
  `StudyBibleDB.lookup_ancient_passages` and `format_ancient_source_lookup`
  (MIT), with the citation grammar of `corpora/` (`Bezalel.Study.Ancient`).
  Same text, except:

    * `limit` must be a whole number (Python truncated 2.5 to 2);
    * a corpus missing from the pack answers without Python's "run
      upgrade_database.py" advice; the outdated-schema case does not arise.

  `result/1` returns the resolved citation (work, sort range, line window)
  and the passages as data (citation, corpus, tag, excerpts, notes, typed
  links, provenance), or the out-of-range neighbours. The user's preferences
  (`Bezalel.Study.Preferences`) set the default `limit`, refuse a citation
  in a switched-off corpus, and decide the scripture labels and editorial
  verdicts (`Bezalel.Study.Ancient.Passages`).
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Ancient, Args, DB, Preferences, Sources}
  alias Bezalel.Study.Ancient.Passages

  @max_limit 10

  @impl true
  def name, do: "lookup_ancient_source"

  @impl true
  def description do
    """
    Look up an ancient source by citation and read it in English with the
    original language: 'Antiquities 18.116', 'Ant. 15.320', 'War 6.316', 'Life 1',
    'Onkelos Gen 49:10', 'CD 6:11', 'Opif. 26', '1 Enoch 1:9', '4 Ezra 7:28',
    'm. Sukkah 4:9'. A work name or abbreviation is followed by a locator in that
    work's numbering; a range returns the overlapping passages in order. A Dead
    Sea Scroll is cited by siglum or name, then fragment or column and line, as
    the ETCBC transcription labels them: '1QM 5:3', '11QMelch ii 18', '4Q174
    frg. 1–2 i 10', '4Q246 frg. 1 ii 1', 'War Scroll 4Q491 frg. 11 i 12'; Hebrew
    and Aramaic only, [ ] is modern reconstruction. Each
    passage carries a date and edition tag (with a canon-status label unless the
    user turned labels off) and any editorial ⚠ notes; caveats and sources are
    printed once. An unknown or ambiguous citation gets a short list of works or
    candidates. To find passages by wording, use search_ancient_sources.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "citation" => %{
          "type" => "string",
          "description" =>
            "Work and locator, e.g. 'Antiquities 18.116', 'Ant. 18.116-119', 'War 6.316', 'Josephus, Life 1', '11Q13 2:18', '4Q174 frg. 1-2 i 10'"
        },
        "corpus" => %{
          "type" => "string",
          "enum" => Ancient.keys(),
          "description" =>
            "Optional corpus to resolve the citation in. Default: every registered corpus"
        },
        "include_original" => %{
          "type" => "boolean",
          "default" => true,
          "description" => "Include the original-language text. Default: true"
        },
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => @max_limit,
          "description" =>
            "Maximum passages. Default: the user's setting (8 unless changed), at most #{@max_limit}"
        },
        "full_text" => %{
          "type" => "boolean",
          "default" => false,
          "description" =>
            "Show whole passages instead of excerpts (English is cut at 1,500 characters, the original at 600). Default: false"
        }
      },
      "required" => ["citation"]
    }
  end

  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)), do: {:ok, render(result)}
  end

  @typedoc """
  The resolved citation (`heading`, `corpus` key, `work` display title,
  `work_key`, `sort_range` and, for a line citation, `window` as
  `%{start:, end:}` sort keys) and either the
  overlapping `passages` with their `total`, or `status` `:out_of_range`
  with the work's imported `first`/`last` keys, the nearest references
  `before`/`after` and any gap notes (`first` nil: no passages imported).
  """
  @type t :: map()

  @doc "The passages `args` cites, under the host's current preferences."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc "The passages `args` cites, under `prefs` (kept in the result as `prefs`)."
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    citation = Args.string(args, "citation")
    corpus_key = Args.optional(args, "corpus")

    with :ok <- Sources.check_tool(prefs, name()),
         :ok <- check(citation, corpus_key),
         :ok <- if(corpus_key, do: Sources.check(prefs, Sources.ancient(corpus_key)), else: :ok),
         {:ok, limit} <- limit(args, prefs) do
      corpora = if corpus_key, do: [Ancient.corpus(corpus_key)], else: Ancient.corpora()
      resolve(citation, corpora, limit, Map.put(args, :prefs, prefs))
    end
  end

  defp check("", _corpus_key) do
    {:error,
     "Please provide a citation such as 'Antiquities 18.116'. Citable works: " <>
       "#{Ancient.citable_works()}."}
  end

  defp check(_citation, nil), do: :ok

  defp check(_citation, corpus_key) do
    if Ancient.corpus(corpus_key),
      do: :ok,
      else:
        {:error,
         "Unsupported ancient-source corpus '#{corpus_key}'. Available corpora: " <>
           "#{Enum.join(Ancient.keys(), ", ")}."}
  end

  defp limit(args, prefs) do
    case Args.integer(args, "limit", Preferences.limit(prefs, @max_limit)) do
      {:ok, limit} when limit in 1..@max_limit//1 -> {:ok, limit}
      _ -> {:error, "'limit' must be an integer from 1 to #{@max_limit}."}
    end
  end

  defp resolve(citation, corpora, limit, args) do
    case Ancient.resolve(citation, corpora) do
      :unknown_work ->
        hint =
          case Ancient.similar_works(citation) do
            [] -> ""
            similar -> " Did you mean #{Enum.join(similar, " or ")}?"
          end

        {:error,
         "Unknown work in citation '#{citation}'.#{hint} Citable works: #{Ancient.citable_works()}."}

      {:ambiguous, candidates} ->
        {:error,
         "Ambiguous citation '#{citation}': it matches " <>
           Enum.map_join(candidates, "; ", &Ancient.candidate/1) <>
           ". Add a collection or work name to choose one."}

      {:bad_locator, [first | _] = candidates} ->
        problem =
          if first.locator_text != "",
            do: "Could not read the locator '#{first.locator_text}'",
            else: "No locator"

        examples = candidates |> Enum.map(&work_example/1) |> Enum.uniq() |> Enum.join(", ")

        {:error,
         "#{problem} in '#{citation}'. Expected: " <>
           Enum.map_join(candidates, "; ", &Ancient.candidate/1) <> "; e.g. #{examples}."}

      {:ok, match} ->
        with :ok <- Sources.check(args.prefs, Sources.ancient(match.corpus.key)),
             {:ok, found} <-
               DB.with_pack(Ancient.pack(match.work), &cited(&1, match, limit, args)),
             do: found
    end
  end

  # A fragment citation needs its label resolved against the pack first.
  defp cited(conn, %{fragment: %{} = fragment} = match, limit, args) do
    case fragment_range(conn, match, fragment) do
      {:ok, range} -> lookup(conn, %{match | sort_range: range}, limit, args)
      {:error, message} -> {:error, message}
    end
  end

  defp cited(conn, match, limit, args), do: lookup(conn, match, limit, args)

  # The sort range of a fragment citation: its label's (or a label range's)
  # ordinal × 1000 + the cited lines, from the passages' `section_number`
  # keys and `book_number` ordinals.
  defp fragment_range(conn, match, %{label: label, lines: lines}) do
    {first, last} = if lines, do: lines, else: {0, 999}

    case label_ordinal(conn, match, label) do
      nil ->
        with nil <- lines,
             [from, to] <- label_range(label),
             low when low != nil <- label_ordinal(conn, match, from),
             high when high != nil and high >= low <- label_ordinal(conn, match, to) do
          {:ok, {low * 1000, high * 1000 + 999}}
        else
          _ -> {:error, unknown_label(conn, match, label)}
        end

      ordinal ->
        {:ok, {ordinal * 1000 + first, ordinal * 1000 + last}}
    end
  end

  defp label_ordinal(conn, match, label) do
    Enum.find_value(Ancient.fragment_keys(label), fn key ->
      row =
        DB.one(
          conn,
          """
          SELECT book_number FROM ancient_source_passages
          WHERE corpus = ? AND work_key = ? AND section_number = ? LIMIT 1
          """,
          [match.corpus.key, match.work.key, key]
        )

      row && row["book_number"]
    end)
  end

  # 'frg. 3–5' as 'frg. 3' to 'frg. 5'; nil unless the label has one dash.
  defp label_range(label) do
    case String.split(label, "–") do
      [from, to] when from != "" and to != "" ->
        fragment? = String.starts_with?(Ancient.fragment_key(from), "f")

        [
          from,
          if(fragment? and not String.starts_with?(Ancient.fragment_key(to), "f"),
            do: "frg. " <> to,
            else: to
          )
        ]

      _ ->
        nil
    end
  end

  defp unknown_label(conn, match, label) do
    labels =
      conn
      |> DB.all(
        """
        SELECT reference FROM ancient_source_passages
        WHERE corpus = ? AND work_key = ? ORDER BY sort_start
        """,
        [match.corpus.key, match.work.key]
      )
      |> Enum.map(&Ancient.reference_label(match.work, &1["reference"]))

    {shown, rest} = Enum.split(labels, 30)
    more = if rest == [], do: "", else: " and #{length(rest)} more"

    "#{match.work.reference_title} has no fragment or column '#{label}'. Its fragments and " <>
      "columns, as ETCBC labels them: #{Enum.join(shown, ", ")}#{more}. Cite one with an " <>
      "optional line, e.g. '#{match.work.reference_title} #{List.first(labels)} 1'."
  end

  # A citation of the work's first imported passage, else its grammar's example.
  defp work_example(match) do
    work = match.work

    first =
      case DB.with_pack(Ancient.pack(work), &first_passage(&1, match.corpus.key, work.key)) do
        {:ok, row} -> row
        {:error, _} -> nil
      end

    locator =
      cond do
        first == nil ->
          work.locator.example

        Ancient.fragment_locator?(work) ->
          Ancient.reference_label(work, first["reference"]) <> " 1"

        true ->
          Ancient.format_range(work.locator, first["sort_start"], first["sort_start"])
      end

    "'#{Ancient.display_title(work)} #{locator}'"
  end

  defp first_passage(conn, corpus, work_key) do
    DB.one(
      conn,
      """
      SELECT reference, sort_start, sort_end FROM ancient_source_passages
      WHERE corpus = ? AND work_key = ? AND sort_start IS NOT NULL
      ORDER BY sort_start LIMIT 1
      """,
      [corpus, work_key]
    )
  end

  defp lookup(conn, match, limit, args) do
    %{corpus: corpus, work: work, sort_range: {start, end_}} = match

    present =
      DB.one(
        conn,
        "SELECT 1 FROM ancient_source_passages WHERE corpus = ? AND sort_start IS NOT NULL LIMIT 1",
        [corpus.key]
      )

    if present == nil do
      {:error, "The #{corpus.label} corpus is not in this device's #{Ancient.pack(work)} pack."}
    else
      work_where = "corpus = ? AND work_key = ?"
      overlap = "#{work_where} AND sort_start <= ? AND sort_end >= ?"
      params = [corpus.key, work.key, end_, start]
      window = Passages.window(corpus, work, start, end_)

      base = %{
        heading: Ancient.heading(match),
        corpus: corpus.key,
        work_key: work.key,
        work: Ancient.display_title(work),
        sort_range: %{start: start, end: end_},
        window: window && %{start: elem(window, 0), end: elem(window, 1)},
        locator:
          if(Ancient.fragment_locator?(work),
            do: match.locator_text,
            else: Ancient.format_range(work.locator, start, end_)
          ),
        prefs: args.prefs
      }

      total =
        DB.one(
          conn,
          "SELECT COUNT(*) AS total FROM ancient_source_passages WHERE #{overlap}",
          params
        )["total"]

      if total == 0 do
        {:ok,
         Map.merge(
           base,
           out_of_range(conn, work_where, corpus.key, work.key, start, end_, params)
         )}
      else
        rows =
          DB.all(
            conn,
            "SELECT * FROM ancient_source_passages WHERE #{overlap} ORDER BY sort_start, sort_end LIMIT ?",
            params ++ [limit]
          )

        passages =
          conn
          |> Passages.annotate(rows)
          |> Enum.map(
            &Passages.passage(&1,
              include_original: Args.flag(args, "include_original", true),
              full_text: Args.flag(args, "full_text", false),
              note_cut: not Args.flag(args, "full_text", false),
              window: window,
              prefs: args.prefs
            )
          )

        {:ok, Map.merge(base, %{status: :ok, total: total, passages: passages})}
      end
    end
  end

  defp out_of_range(conn, work_where, corpus, work_key, start, end_, params) do
    bounds =
      DB.one(
        conn,
        "SELECT MIN(sort_start) AS first, MAX(sort_end) AS last FROM ancient_source_passages WHERE #{work_where}",
        [corpus, work_key]
      )

    before =
      DB.one(
        conn,
        "SELECT reference FROM ancient_source_passages WHERE #{work_where} AND sort_end < ? ORDER BY sort_end DESC LIMIT 1",
        [corpus, work_key, start]
      )

    after_ =
      DB.one(
        conn,
        "SELECT reference FROM ancient_source_passages WHERE #{work_where} AND sort_start > ? ORDER BY sort_start LIMIT 1",
        [corpus, work_key, end_]
      )

    gap_notes =
      DB.all(
        conn,
        """
        SELECT DISTINCT citation, kind, note, contrast, aligned FROM ancient_source_notes
        WHERE #{work_where} AND kind = 'gap' AND sort_start <= ? AND sort_end >= ?
        ORDER BY sort_start
        """,
        params
      )

    %{
      status: :out_of_range,
      first: bounds["first"],
      last: bounds["last"],
      before: before && before["reference"],
      after: after_ && after_["reference"],
      gap_notes: gap_notes
    }
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{status: :out_of_range, first: nil} = r),
    do: "No #{r.work} passages are imported in this database."

  def render(%{status: :out_of_range} = r) do
    {_corpus, work} = corpus_work(r)

    nearest =
      for {side, value} <- [{"preceding", r.before}, {"following", r.after}],
          value,
          do: "#{side} #{value}"

    gaps = Enum.map_join(r.gap_notes, &" ⚠ #{&1["citation"]}: #{&1["note"]}")

    runs =
      if Ancient.fragment_locator?(work),
        do: "",
        else:
          " Imported #{r.work} runs #{r.work} #{Ancient.format_range(work.locator, r.first, r.last)}"

    "No passage covers #{r.heading}.#{runs}" <>
      if(nearest != [],
        do:
          "#{if runs == "", do: " Nearest", else: "; nearest"} passages: #{Enum.join(nearest, ", ")}.",
        else: if(runs == "", do: "", else: ".")
      ) <>
      if(work.coverage_note != "", do: " #{work.coverage_note}", else: "") <> gaps
  end

  def render(r) do
    {corpus, work} = corpus_work(r)
    count = r.total
    shown = length(r.passages)

    cited =
      if Ancient.fragment_locator?(work),
        do: "#{corpus.label}, #{work.title}, #{work.reference_title} #{r.locator}",
        else: "#{corpus.label}, #{work.title} (#{work.locator.name} #{r.locator})"

    note = "#{cited}: #{count} overlapping passage#{if count != 1, do: "s"}"

    header =
      ["## #{r.heading}", "", "*#{note}*", ""] ++
        if count > shown,
          do: [
            "*Showing the first #{shown} of #{count} overlapping passages; cite a " <>
              "narrower range or raise limit (at most #{@max_limit}) to read more.*",
            ""
          ],
          else: []

    Passages.render(header, r.passages, nil, r.prefs, fn passage, shown ->
      resume =
        if Ancient.fragment_locator?(work),
          do: " Continue from #{passage.reference}.",
          else:
            " Continue from #{r.work} " <>
              "#{Ancient.format_range(work.locator, passage.sort_start, passage.sort_start)}."

      "*Stopped at the 12,000-character response budget after #{shown} passages.#{resume}*"
    end)
  end

  defp corpus_work(r) do
    corpus = Ancient.corpus(r.corpus)
    {corpus, Ancient.work(corpus, r.work_key)}
  end
end
