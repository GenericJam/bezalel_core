defmodule Bezalel.Study.Tools.LookupAncientSource do
  @moduledoc """
  `lookup_ancient_source`: an ancient source by citation ('Antiquities
  18.116', 'CD 6:11', 'm. Sukkah 4:9'), the passages of the ancient pack
  overlapping it, in citation order. No full-text search, so it works on a
  device whose SQLite lacks FTS5.

  Ported from studybible-mcp's `handle_lookup_ancient_source`,
  `StudyBibleDB.lookup_ancient_passages` and `format_ancient_source_lookup`
  (MIT), with the citation grammar of `corpora/` (`Bezalel.Study.Ancient`).
  Same text, except:

    * `limit` must be a whole number (Python truncated 2.5 to 2);
    * a corpus missing from the pack answers without Python's "run
      upgrade_database.py" advice; the outdated-schema case does not arise.

  `result/1` returns the resolved citation (work, sort range, line window)
  and the passages as data (citation, corpus, tag, excerpts, notes, typed
  links, provenance), or the out-of-range neighbours.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Ancient, Args, DB}
  alias Bezalel.Study.Ancient.Passages

  @default_limit 4
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
    work's numbering; a range returns the overlapping passages in order. None is
    Scripture: each passage carries a canon, date and edition tag and any
    editorial ⚠ notes; caveats and sources are printed once. An unknown or
    ambiguous citation gets a short list of works or candidates. To find passages
    by wording, use search_ancient_sources.\
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
            "Work and locator, e.g. 'Antiquities 18.116', 'Ant. 18.116-119', 'War 6.316', 'Josephus, Life 1'"
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
          "default" => @default_limit,
          "description" => "Maximum passages. Default: #{@default_limit}"
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
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
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

  @doc "The passages `args` cites."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    citation = Args.string(args, "citation")
    corpus_key = Args.optional(args, "corpus")

    with :ok <- check(citation, corpus_key),
         {:ok, limit} <- limit(args) do
      corpora = if corpus_key, do: [Ancient.corpus(corpus_key)], else: Ancient.corpora()
      resolve(citation, corpora, limit, args)
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

  defp limit(args) do
    case Args.integer(args, "limit", @default_limit) do
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
        with {:ok, found} <- DB.with_pack(:ancient, &lookup(&1, match, limit, args)), do: found
    end
  end

  # A citation of the work's first imported passage, else its grammar's example.
  defp work_example(match) do
    work = match.work

    first =
      case DB.with_pack(:ancient, &first_passage(&1, match.corpus.key, work.key)) do
        {:ok, row} -> row
        {:error, _} -> nil
      end

    locator =
      if first,
        do: Ancient.format_range(work.locator, first["sort_start"], first["sort_start"]),
        else: work.locator.example

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
      {:error, "The #{corpus.label} corpus is not in this device's ancient pack."}
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
        locator: Ancient.format_range(work.locator, start, end_)
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
              window: window
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

    "No passage covers #{r.heading}. Imported #{r.work} runs " <>
      "#{r.work} #{Ancient.format_range(work.locator, r.first, r.last)}" <>
      if(nearest != [], do: "; nearest passages: #{Enum.join(nearest, ", ")}.", else: ".") <>
      if(work.coverage_note != "", do: " #{work.coverage_note}", else: "") <> gaps
  end

  def render(r) do
    {corpus, work} = corpus_work(r)
    count = r.total
    shown = length(r.passages)

    note =
      "#{corpus.label}, #{work.title} (#{work.locator.name} #{r.locator}): #{count} overlapping " <>
        "passage#{if count != 1, do: "s"}"

    header =
      ["## #{r.heading}", "", "*#{note}*", ""] ++
        if count > shown,
          do: [
            "*Showing the first #{shown} of #{count} overlapping passages; cite a " <>
              "narrower range or raise limit (at most #{@max_limit}) to read more.*",
            ""
          ],
          else: []

    Passages.render(header, r.passages, nil, fn passage, shown ->
      resume =
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
