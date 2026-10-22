defmodule Bezalel.Study.Tools.GetTextualVariant do
  @moduledoc """
  `get_textual_variant`: a verse's catalogued textual-variant record
  (manuscript readings and witnesses, citations, judgments,
  interpretations, translation decisions) and NT↔OT quotation alignments,
  each kind kept apart (the notes pack's `textual_*` and
  `nt_ot_lxx_quote_hints` tables).

  Ported from studybible-mcp's `handle_get_textual_variant`,
  `get_textual_variant_cases`, `get_nt_ot_lxx_quote_hints` and
  `format_textual_variant_cases` (MIT). Same text. Their "Textual-variant
  data is unavailable" message (legacy, missing or empty tables) is gone:
  the tables are in the notes pack, so a missing pack is the pack error.

  `result/1` returns the cases and alignments as data.

  Every witness, sourced statement and translation decision has its
  `Source:` line (`citations/1`); a witness that is a Dead Sea Scroll (by
  the scrolls pack's sigla and names, when it is on the device) also cites
  its manuscript's page.

  Changed for Bezalel: the dataset's "Heiser Literal Translation (HLT)"
  decisions are an unpublished, AI-assisted draft, not Heiser's: they are
  labelled so (their rationale's "the HLT" is "the draft") and cite the
  verse's Hebrew, Greek and scroll witnesses to check them against
  (`Bezalel.Study.Citations.hlt/2`).

  Added for Bezalel: from the witnesses pack when it is on the device (else
  nothing, silently), after the notes pack's cases, the UBS Hebrew Old
  Testament Text Project's entries at an Old Testament verse (each reading
  with the base translations that follow it, then the committee's rating
  and factors, explained from the report's introduction, as its judgment)
  and the SBLGNT apparatus's variation units at a New Testament verse (the
  SBLGNT's reading and each variant, with the editions that print them). A
  verse with no notes-pack case returns these alone; without the notes pack
  (or with one that can't be read) it returns them with a note that the
  curated cases are missing, and is the notes pack's error only when the
  witnesses pack has nothing for the verse either.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, Citation, Citations, DB, Format, Patterns, Reference, Witnesses}

  # Cases that record how agreed text is read, not a manuscript variant.
  @interpretive_case_keys ["MT_preserved", "translation_choice"]

  # The dataset's name for the unpublished draft, and what the tool calls it.
  @draft_translation "Heiser Literal Translation"
  @draft_label "Unpublished draft rendering (AI-assisted), not Heiser's"

  @impl true
  def name, do: "get_textual_variant"

  @impl true
  def description do
    """
    Retrieve a textual-variant record without conflating evidence and interpretation.

    WHAT IT RETURNS for a given verse reference:
    - Manuscript evidence: distinct readings and the manuscript witnesses attached to each reading
    - NT citation evidence: New Testament quotations of the verse, kept apart from manuscript copies
    - Indirect evidence: material bearing on a reading's text form without witnessing this verse (e.g. a scroll attesting a short edition elsewhere in the book)
    - Not preserved in: corpora with no surviving copy of the verse (e.g. no Dead Sea Scroll)
    - Critical judgments: text-critical conclusions that carry a source citation
    - Unsourced dataset summary: uncited editorial summaries, labelled as not verified against published text-critical scholarship
    - Theological interpretations: explicitly labelled interpretations, never presented as manuscript evidence
    - Author-specific claims: named-author arguments, separate from critical judgments
    - Translation decisions: a translation's selected reading and rationale
    - NT quotation alignment: separately catalogued links showing which form (an LXX form or the MT) an NT quotation follows
    - Translation and interpretation notes: how a contested verse is read or rendered (e.g. divine-council language at Psalm 82:6); shown separately, after any manuscript variant at the verse, never as one
    - UBS Hebrew Old Testament Text Project (HOTTP), Old Testament: the forms of the text the committee compared, with the base translations following each, then the committee's rating (A–D) of the reading it preferred and the factors behind its decision, explained, as its judgment
    - SBLGNT apparatus, New Testament: at each variation unit, the SBL Greek New Testament's reading and the variants, each with the printed editions (Westcott–Hort, Tregelles, NA28, Robinson–Pierpont…) that read it; editions, not manuscripts

    Sections with nothing catalogued are omitted. Each manuscript-variant witness
    keeps the dataset's raw support label. A witness date describes the witness
    record; it does not by itself date the underlying reading.

    Relevant where a New Testament quotation does not match the Old Testament verse
    it quotes (e.g. why Hebrews 10:5 says "a body you prepared" where Psalm 40:6 says
    "ears you have dug"), and to questions about how the Hebrew, Greek, and Qumran
    textual traditions differ at a specific verse.

    `lookup_verse` notes when a verse has a catalogued variant case or a quotation
    alignment.\
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
            "A single verse — either the OT verse (e.g., 'Psalm 40:6', 'Deuteronomy 32:43', 'Isaiah 61:1') or the NT verse that quotes it (e.g., 'Hebrews 10:5', 'Hebrews 1:6', 'Luke 4:18'). Both sides return the same variant case."
        }
      },
      "required" => ["reference"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args) do
      Citations.details(render(result), result, citations(result))
    end
  end

  @doc "Is a case with `case_key` translation/interpretation notes rather than a variant?"
  @spec interpretive?(String.t()) :: boolean()
  def interpretive?(case_key), do: case_key in @interpretive_case_keys

  @typedoc """
  An evidence row: `support` is the dataset's raw support label,
  `reading_key`/`tradition` the reading it attaches to (nil for "not
  preserved").
  """
  @type witness :: %{
          witness: String.t(),
          evidence_type: String.t(),
          support: String.t() | nil,
          date: String.t() | nil,
          citation: String.t() | nil,
          url: String.t() | nil,
          reading_key: String.t() | nil,
          tradition: String.t() | nil,
          scroll: scroll() | nil
        }

  @typedoc "A Dead Sea Scroll witness's manuscript in the scrolls pack (`name` nil: no Leon Levy page)."
  @type scroll :: %{siglum: String.t(), name: String.t() | nil}

  @type reading :: %{
          key: String.t(),
          tradition: String.t(),
          text: String.t(),
          original_text: String.t() | nil,
          language: String.t() | nil,
          witnesses: [witness()]
        }

  @typedoc "An attributed statement: a judgment, interpretation or claim."
  @type statement :: %{
          text: String.t(),
          attribution: String.t() | nil,
          citation: String.t() | nil,
          url: String.t() | nil
        }

  @type variant_case :: %{
          id: integer(),
          reference: String.t(),
          case_key: String.t(),
          significance: String.t() | nil,
          kind: :manuscript | :interpretive,
          readings: [reading()],
          citation_evidence: [witness()],
          indirect_evidence: [witness()],
          not_preserved_in: [witness()],
          critical_judgments: [statement()],
          unsourced_summaries: [statement()],
          theological_interpretations: [statement()],
          author_claims: [statement()],
          translation_decisions: [
            %{
              translation: String.t(),
              draft: boolean(),
              preferred_reading: String.t(),
              rationale: String.t() | nil
            }
          ]
        }

  @typedoc "An NT↔OT quotation alignment (`follows_lxx`: the NT follows an LXX form)."
  @type quotation :: %{
          nt_reference: String.t(),
          nt_display: String.t(),
          ot_reference: String.t(),
          ot_display: String.t(),
          follows_lxx: boolean(),
          divergence_type: String.t() | nil,
          divergence_note: String.t() | nil
        }

  @typedoc """
  A verse's record: the notes pack's `cases` and `quotations`; from the
  witnesses pack, its `hottp` entries and `apparatus` units, with the
  `glossary` (`ratings`, `factors`) and `witness_sources` (by key) they
  need (all empty without the pack).
  """
  @type t :: %{
          reference: String.t(),
          cases: [variant_case()],
          quotations: [quotation()],
          hottp: [Witnesses.entry()],
          apparatus: [Witnesses.unit()],
          glossary: %{ratings: map(), factors: map()},
          witness_sources: %{String.t() => Witnesses.source()},
          notes: :on | :missing
        }

  @doc """
  The cases and quotation alignments catalogued for `args`' verse (an NT
  verse also reaches the cases of the OT verse it quotes); none is a result
  too. A missing or multi-verse reference is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    reference = Args.reference(args)
    normalized = Reference.normalize(reference)

    cond do
      reference == "" ->
        {:error, "Please provide a verse reference (OT or NT)."}

      not Regex.match?(Patterns.get(:single_verse_reference), normalized) ->
        {:error,
         "'#{reference}' is not a single-verse reference. get_textual_variant " <>
           "takes one verse, e.g. 'Deuteronomy 32:8' or 'Hebrews 10:5'."}

      true ->
        case DB.with_pack(:notes, &record(&1, reference, normalized)) do
          {:ok, record} ->
            {:ok, record |> Map.put(:notes, :on) |> add_scrolls() |> add_witnesses(normalized)}

          {:error, message} ->
            witnesses_only(reference, normalized, message)
        end
    end
  end

  # Without a readable notes pack, the witnesses pack's data for the verse
  # with a note that the curated cases are missing; nothing there either is
  # the notes pack's error.
  defp witnesses_only(reference, normalized, notes_error) do
    record =
      add_witnesses(
        %{reference: reference, cases: [], quotations: [], notes: :missing},
        normalized
      )

    if record.hottp == [] and record.apparatus == [],
      do: {:error, notes_error},
      else: {:ok, record}
  end

  @no_witnesses %{
    hottp: [],
    apparatus: [],
    glossary: %{ratings: %{}, factors: %{}},
    witness_sources: %{}
  }

  # The verse's HOTTP entries and apparatus units, from the witnesses pack
  # (none when it's missing or can't be read).
  defp add_witnesses(record, normalized) do
    read = fn conn ->
      tables = ~w(hottp_entries hottp_alternatives hottp_verses hottp_ratings hottp_factors
                  sblgnt_apparatus)

      with :ok <- Witnesses.check(conn, tables) do
        hottp = Witnesses.hottp(conn, normalized)

        {:ok,
         %{
           hottp: hottp,
           apparatus: Witnesses.apparatus(conn, normalized),
           glossary:
             if(hottp == [],
               do: @no_witnesses.glossary,
               else: %{ratings: Witnesses.ratings(conn), factors: Witnesses.factors(conn)}
             ),
           witness_sources: Witnesses.sources(conn)
         }}
      end
    end

    case DB.with_pack(:witnesses, read) do
      {:ok, {:ok, witnesses}} -> Map.merge(record, witnesses)
      _missing -> Map.merge(record, @no_witnesses)
    end
  end

  # Each witness's Dead Sea Scroll manuscript (`scroll`), by its siglum or
  # name in the scrolls pack ('4QDeutj', '1Q8 (1QIsa^b)'); none without
  # the pack.
  defp add_scrolls(%{cases: []} = record), do: record

  defp add_scrolls(%{cases: cases} = record) do
    manuscripts = scroll_manuscripts()

    put = fn witnesses ->
      Enum.map(witnesses, &Map.put(&1, :scroll, scroll(&1.witness, manuscripts)))
    end

    cases =
      for c <- cases do
        %{
          c
          | readings: Enum.map(c.readings, &%{&1 | witnesses: put.(&1.witnesses)}),
            citation_evidence: put.(c.citation_evidence),
            indirect_evidence: put.(c.indirect_evidence),
            not_preserved_in: put.(c.not_preserved_in)
        }
      end

    %{record | cases: cases}
  end

  defp scroll_manuscripts do
    read = fn conn ->
      with :ok <- DB.check_tables(conn, :scrolls, ["dss_biblical_manuscripts"]) do
        conn |> DB.all("SELECT siglum, name FROM dss_biblical_manuscripts") |> scroll_index()
      end
    end

    case DB.with_pack(:scrolls, read) do
      {:ok, %{} = manuscripts} -> manuscripts
      _missing -> %{}
    end
  end

  # Each manuscript under its siglum and its name.
  defp scroll_index(rows) do
    for row <- rows,
        key <- [row["siglum"], row["name"]],
        Format.present?(key),
        into: %{},
        do: {scroll_key(key), %{siglum: row["siglum"], name: blank_nil(row["name"])}}
  end

  # 'Name' or 'Name (alias, note)': the name, then the parenthesis's first word.
  defp scroll(witness, manuscripts) do
    [main | rest] = String.split(witness, " (", parts: 2)
    aside = Enum.map(rest, &(&1 |> String.split([")", " ", ","]) |> hd()))
    Enum.find_value([main | aside], &manuscripts[scroll_key(&1)])
  end

  defp scroll_key(text), do: text |> String.replace("^", "") |> String.trim() |> String.downcase()

  defp blank_nil(value), do: if(Format.present?(value), do: value)

  defp record(conn, reference, normalized) do
    quotations = quotations(conn, normalized)

    # A query may use the NT side of a quotation alignment: its OT variant
    # cases, without merging the alignment into the evidence.
    cases =
      case cases(conn, normalized) do
        [] ->
          quotations
          |> Enum.flat_map(&cases(conn, &1.ot_reference))
          |> Enum.uniq_by(& &1.id)

        cases ->
          cases
      end

    %{reference: reference, cases: cases, quotations: quotations}
  end

  @doc "The quotation alignments whose NT or OT side is the pack reference `normalized`."
  @spec quotations(DB.conn(), String.t()) :: [quotation()]
  def quotations(conn, normalized) do
    conn
    |> DB.all(
      "SELECT * FROM nt_ot_lxx_quote_hints WHERE nt_reference = ? OR ot_reference = ? ORDER BY id",
      [normalized, normalized]
    )
    |> Enum.map(&quotation/1)
  end

  @doc "A `nt_ot_lxx_quote_hints` row as a `t:quotation/0`."
  @spec quotation(DB.row()) :: quotation()
  def quotation(row) do
    %{
      nt_reference: row["nt_reference"],
      nt_display: row["nt_display"],
      ot_reference: row["ot_reference"],
      ot_display: row["ot_display"],
      follows_lxx: row["follows_lxx"] not in [nil, 0],
      divergence_type: row["divergence_type"],
      divergence_note: row["divergence_note"]
    }
  end

  defp cases(conn, normalized) do
    conn
    |> DB.all("SELECT * FROM textual_variant_cases WHERE reference = ? ORDER BY id", [normalized])
    |> Enum.map(&load_case(conn, &1))
  end

  defp load_case(conn, row) do
    id = row["id"]

    readings =
      DB.all(conn, "SELECT * FROM textual_variant_readings WHERE case_id = ? ORDER BY id", [id])

    by_id = Map.new(readings, &{&1["id"], &1})

    witnesses =
      conn
      |> DB.all(
        """
        SELECT reading_id, witness, evidence_type, reading_support,
               approximate_date, source_citation, source_url
        FROM textual_variant_witnesses
        WHERE case_id = ? ORDER BY id
        """,
        [id]
      )
      |> Enum.map(&witness(&1, by_id[&1["reading_id"]]))

    judgments =
      conn
      |> DB.all(
        """
        SELECT judgment, attribution, source_citation, source_url
        FROM textual_critical_judgments WHERE case_id = ? ORDER BY id
        """,
        [id]
      )
      |> Enum.map(&statement(&1, "judgment"))

    %{
      id: id,
      reference: row["reference"],
      case_key: row["case_key"],
      significance: row["significance"],
      kind: if(interpretive?(row["case_key"]), do: :interpretive, else: :manuscript),
      readings:
        for reading <- readings do
          %{
            key: reading["reading_key"],
            tradition: reading["tradition"],
            text: reading["text"],
            original_text: reading["original_text"],
            language: reading["language"],
            witnesses:
              Enum.filter(
                witnesses,
                &(&1.evidence_type == "manuscript" and &1.reading_key == reading["reading_key"])
              )
          }
        end,
      citation_evidence: Enum.filter(witnesses, &(&1.evidence_type == "citation")),
      indirect_evidence: Enum.filter(witnesses, &(&1.evidence_type == "indirect")),
      not_preserved_in:
        Enum.filter(witnesses, &(&1.evidence_type not in ["manuscript", "citation", "indirect"])),
      critical_judgments: Enum.filter(judgments, &Format.present?(&1.citation)),
      unsourced_summaries: Enum.reject(judgments, &Format.present?(&1.citation)),
      theological_interpretations:
        conn
        |> DB.all(
          """
          SELECT interpretation, attribution, source_citation, source_url
          FROM textual_theological_interpretations WHERE case_id = ? ORDER BY id
          """,
          [id]
        )
        |> Enum.map(&statement(&1, "interpretation")),
      author_claims:
        conn
        |> DB.all(
          """
          SELECT author, claim, source_citation, source_url
          FROM textual_author_claims WHERE case_id = ? ORDER BY id
          """,
          [id]
        )
        |> Enum.map(
          &%{
            text: &1["claim"],
            attribution: &1["author"],
            citation: &1["source_citation"],
            url: &1["source_url"]
          }
        ),
      translation_decisions:
        conn
        |> DB.all(
          """
          SELECT translation, preferred_reading, rationale
          FROM textual_translation_decisions WHERE case_id = ? ORDER BY id
          """,
          [id]
        )
        |> Enum.map(&decision/1)
    }
  end

  defp witness(row, reading) do
    %{
      witness: row["witness"],
      evidence_type: row["evidence_type"],
      support: row["reading_support"],
      date: row["approximate_date"],
      citation: row["source_citation"],
      url: row["source_url"],
      reading_key: reading && reading["reading_key"],
      tradition: reading && reading["tradition"]
    }
  end

  defp statement(row, field) do
    %{
      text: row[field],
      attribution: row["attribution"],
      citation: row["source_citation"],
      url: row["source_url"]
    }
  end

  defp decision(row) do
    draft = String.starts_with?(row["translation"] || "", @draft_translation)

    %{
      translation: if(draft, do: @draft_label, else: row["translation"]),
      draft: draft,
      preferred_reading: row["preferred_reading"],
      rationale: if(draft, do: undraft(row["rationale"]), else: row["rationale"])
    }
  end

  # The dataset's rationales call the draft "the HLT".
  defp undraft(nil), do: nil

  defp undraft(text),
    do:
      String.replace(
        text,
        ["the HLT", "The HLT", "HLT"],
        &if(&1 == "the HLT", do: "the draft", else: "The draft")
      )

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{reference: reference, cases: [], quotations: [], hottp: [], apparatus: []}) do
    "No textual-variant case or NT quotation alignment is catalogued for #{reference}."
  end

  def render(%{reference: reference, cases: cases, quotations: quotations} = result) do
    {interpretive, variants} = Enum.split_with(cases, &(&1.kind == :interpretive))

    title =
      if cases != [] and variants == [] and result.hottp == [] and result.apparatus == [],
        do: "# Translation and interpretation notes for #{reference}",
        else: "# Textual variant record for #{reference}"

    shown = shown(variants)

    lines =
      [title, ""] ++
        if(Map.get(result, :notes) == :missing,
          do: [
            "*The notes study pack (studybible-mcp's curated textual-variant cases and " <>
              "quotation alignments) isn't on this device, so only the witnesses pack's data " <>
              "is shown; tell the user if the curated cases matter.*",
            ""
          ],
          else: []
        ) ++
        Enum.flat_map(variants, &variant_lines/1) ++
        Enum.flat_map(interpretive, &interpretive_lines(&1, shown[&1.reference])) ++
        hottp_lines(result) ++
        apparatus_lines(result) ++
        quotation_lines(quotations)

    lines |> Enum.join("\n") |> String.trim_trailing()
  end

  @doc """
  The citations of every witness, sourced statement and translation
  decision `render/1` shows, in its order.
  """
  @spec citations(t()) :: [Citation.t()]
  def citations(%{cases: cases} = result) do
    {interpretive, variants} = Enum.split_with(cases, &(&1.kind == :interpretive))
    shown = shown(variants)

    Enum.flat_map(variants, fn c ->
      (Enum.flat_map(c.readings, & &1.witnesses) ++ c.citation_evidence ++ c.indirect_evidence)
      |> Enum.flat_map(&witness_citations/1)
      |> Kernel.++(interpretation_citations(c))
    end) ++
      Enum.flat_map(interpretive, fn c ->
        (Enum.flat_map(texts(c, shown[c.reference]), & &1.witnesses) ++ c.citation_evidence)
        |> Enum.flat_map(&witness_citations/1)
        |> Kernel.++(interpretation_citations(c))
      end) ++
      Enum.flat_map(Map.get(result, :hottp, []), &hottp_citations(&1, result)) ++
      Enum.flat_map(Map.get(result, :apparatus, []), &[apparatus_citation(&1, result)])
  end

  # The readings each verse's variants print, which its notes then skip.
  defp shown(variants) do
    Enum.reduce(variants, %{}, fn c, acc ->
      readings = MapSet.new(c.readings, &{&1.text, &1.original_text})
      Map.update(acc, c.reference, readings, &MapSet.union(&1, readings))
    end)
  end

  defp texts(c, shown) do
    Enum.reject(
      c.readings,
      &MapSet.member?(shown || MapSet.new(), {&1.text, &1.original_text})
    )
  end

  defp interpretation_citations(c) do
    Enum.flat_map(c.critical_judgments, &stored/1) ++
      Enum.flat_map(c.translation_decisions, &decision_citations(&1, c)) ++
      Enum.flat_map(c.author_claims, &stored/1) ++
      Enum.flat_map(c.theological_interpretations, &stored/1)
  end

  # A witness's stored source, and its manuscript's page for a Dead Sea Scroll.
  defp witness_citations(w), do: stored(w) ++ scroll_citations(w)

  defp scroll_citations(%{scroll: %{siglum: siglum, name: name}}) do
    label =
      if name == nil or String.downcase(name) == String.downcase(siglum),
        do: name || siglum,
        else: "#{siglum} (#{name})"

    [Citations.dss_manuscript(siglum, label, leon_levy: name != nil)]
  end

  defp scroll_citations(_witness), do: []

  # A statement's or witness's stored citation and URL.
  defp stored(item) do
    cond do
      Format.present?(item.citation) -> [Citations.textual(item.citation, item.url)]
      Format.present?(item.url) -> [Citations.textual(item.url, item.url)]
      true -> []
    end
  end

  # A draft rendering cites the verse's originals and its scroll witnesses.
  defp decision_citations(%{draft: true}, c) do
    scrolls =
      c.readings
      |> Enum.flat_map(& &1.witnesses)
      |> Enum.flat_map(&scroll_citations/1)
      |> Citations.dedupe()

    [Citations.hlt(c.reference, scrolls)]
  end

  defp decision_citations(_decision, _c), do: []

  defp source_lines(citations) do
    case Citation.source_line(citations) do
      "" -> []
      line -> ["  - " <> line]
    end
  end

  defp variant_lines(c) do
    ["## Variant at #{c.reference}", "**Case key:** #{c.case_key}"] ++
      significance(c) ++
      ["", "### Manuscript evidence"] ++
      reading_lines(c.readings) ++
      citation_lines(c) ++
      indirect_lines(c.indirect_evidence) ++
      not_preserved_lines(c.not_preserved_in) ++ interpretation_lines(c) ++ ["", "---", ""]
  end

  defp reading_lines([]), do: ["*No manuscript readings catalogued.*"]

  defp reading_lines(readings) do
    Enum.flat_map(readings, fn reading ->
      ["", "#### #{reading.tradition}", reading.text] ++
        original(reading) ++ manuscript_witness_lines(reading.witnesses)
    end)
  end

  defp manuscript_witness_lines([]), do: []

  defp manuscript_witness_lines(witnesses) do
    [
      "\n**Manuscript witnesses for this reading:**"
      | Enum.flat_map(witnesses, &witness_lines(&1, ""))
    ]
  end

  defp indirect_lines([]), do: []

  defp indirect_lines(witnesses) do
    [
      "",
      "### Indirect evidence",
      "*Not a direct witness to this verse; bears on the text form behind a reading.*"
    ] ++ Enum.flat_map(witnesses, &witness_lines(&1, "bears on the #{tradition(&1)} reading"))
  end

  defp not_preserved_lines([]), do: []

  defp not_preserved_lines(witnesses) do
    names =
      Enum.map_join(
        witnesses,
        ", ",
        &Regex.replace(Patterns.get(:none_preserved), &1.witness, "")
      )

    ["", "**Not preserved in:** #{names}"]
  end

  # An agreed-text case: the text, then the attributed layers. `shown` holds
  # the readings a variant at the same verse already printed: the notes then
  # point back to it and skip those texts.
  defp interpretive_lines(c, shown) do
    banner =
      if shown == nil,
        do:
          "*Not a manuscript variant: the witnesses agree with the Masoretic Text " <>
            "here. These notes record how the verse is read and translated.*",
        else:
          "*Not manuscript evidence: these notes record how the verse is read and " <>
            "translated. The textual evidence at this verse is in the variant record above.*"

    texts = Enum.flat_map(texts(c, shown), &text_lines/1)

    [
      "## Translation and interpretation notes at #{c.reference}",
      banner,
      "**Case key:** #{c.case_key}"
    ] ++
      significance(c) ++
      texts ++ citation_lines(c) ++ interpretation_lines(c) ++ ["", "---", ""]
  end

  defp text_lines(reading) do
    ["", "### Text (#{reading.tradition})", reading.text] ++
      original(reading) ++ agreeing_lines(reading.witnesses)
  end

  defp agreeing_lines([]), do: []

  defp agreeing_lines(witnesses) do
    ["\n**Witnesses agreeing with this text:** " <> Enum.map_join(witnesses, ", ", &dated/1)] ++
      source_lines(Enum.flat_map(witnesses, &witness_citations/1))
  end

  defp dated(w), do: if(Format.present?(w.date), do: "#{w.witness} (#{w.date})", else: w.witness)

  defp original(reading) do
    if Format.present?(reading.original_text),
      do: ["\n**Original-language text:** `#{reading.original_text}`"],
      else: []
  end

  defp significance(c) do
    if Format.present?(c.significance),
      do: ["**Significance classification:** #{c.significance}"],
      else: []
  end

  defp citation_lines(%{citation_evidence: []}), do: []

  defp citation_lines(c) do
    [
      "",
      "### NT citation evidence",
      "*New Testament quotations show how the verse was cited; " <>
        "they are not manuscript copies of it.*"
    ] ++
      Enum.flat_map(
        c.citation_evidence,
        &witness_lines(&1, "quotes the #{tradition(&1)} reading")
      )
  end

  defp tradition(witness), do: if(witness.reading_key, do: Format.s(witness.tradition), else: "?")

  defp witness_lines(w, note) do
    line =
      "- **#{w.witness}**" <>
        if(Format.present?(w.date), do: " (#{w.date})", else: "") <>
        if(note != "", do: " — #{note}", else: "") <>
        if(Format.present?(w.support), do: " (dataset label: `#{w.support}`)", else: "")

    [line] ++ source_lines(witness_citations(w))
  end

  defp interpretation_lines(c) do
    section(c.critical_judgments, "### Critical judgments", &sourced/1) ++
      section(
        c.unsourced_summaries,
        "### Unsourced dataset summary (not verified against published text-critical scholarship)",
        &["- #{&1.text}"]
      ) ++
      section(c.translation_decisions, "### Translation decisions", fn d ->
        ["- **#{d.translation}:** #{d.preferred_reading}"] ++
          if(Format.present?(d.rationale), do: ["  - Rationale: #{d.rationale}"], else: []) ++
          source_lines(decision_citations(d, c))
      end) ++
      section(c.author_claims, "### Author-specific claims", fn claim ->
        ["- **#{claim.attribution}.** #{claim.text}" | source_lines(stored(claim))]
      end) ++
      section(c.theological_interpretations, "### Theological interpretations", &sourced/1)
  end

  defp section([], _heading, _lines), do: []
  defp section(items, heading, lines), do: ["", heading | Enum.flat_map(items, lines)]

  defp sourced(item) do
    attribution = if Format.present?(item.attribution), do: item.attribution, else: "Unattributed"
    ["- **Attribution: #{attribution}.** #{item.text}" | source_lines(stored(item))]
  end

  defp quotation_lines([]), do: []

  defp quotation_lines(quotations) do
    ["## NT quotation alignment", ""] ++
      for q <- quotations do
        type = if Format.present?(q.divergence_type), do: q.divergence_type, else: "alignment"

        note =
          if Format.present?(q.divergence_note),
            do: q.divergence_note,
            else: "No note catalogued."

        "- **#{q.nt_display}** quotes **#{q.ot_display}** — *#{type}*: #{note}"
      end
  end

  # --- HOTTP ------------------------------------------------------------------

  defp hottp_lines(%{hottp: []}), do: []

  defp hottp_lines(%{hottp: entries, glossary: glossary} = result) do
    [
      "## UBS Hebrew Old Testament Text Project (HOTTP) at #{hd(entries).reference}",
      "*The committee's entries (UBS, 1969–1980): the forms of the text it compared, each " <>
        "with how the base translations render it; then its judgment, kept apart: the rating " <>
        "of the form it judged the earliest attested text, and some of the factors behind its " <>
        "decision for or against a form. [ ] around Hebrew: a form reconstructed from the " <>
        "versions, with no Hebrew witness.*",
      ""
    ] ++
      Enum.flat_map(entries, &hottp_entry_lines(&1, result)) ++
      factor_lines(entries, glossary.factors) ++ ["", "---", ""]
  end

  defp hottp_entry_lines(entry, result) do
    numbering =
      if entry.source_reference != entry.reference,
        do: " (Hebrew numbering #{entry.source_reference})",
        else: ""

    ["### HOTTP entry #{entry.id}#{numbering}", "", "**Readings compared:**"] ++
      Enum.flat_map(entry.alternatives, &alternative_lines/1) ++
      judgment_lines(entry, result.glossary.ratings) ++
      source_lines(hottp_citations(entry, result)) ++ [""]
  end

  defp alternative_lines(alternative) do
    renderings =
      alternative.renderings
      |> Enum.filter(&Format.present?(&1.text))
      |> Enum.map_join("; ", &"#{&1.version} “#{&1.text}”")

    ["- #{alternative.position}. `#{alternative.hebrew || "(no Hebrew form given)"}`"] ++
      if(Format.present?(alternative.literal),
        do: ["  - Literal English (HOTTP): #{alternative.literal}"],
        else: []
      ) ++
      if(renderings != "", do: ["  - Base translations rendering it: #{renderings}"], else: [])
  end

  defp judgment_lines(entry, ratings) do
    rated =
      for a <- entry.alternatives, Format.present?(a.rating) do
        meaning =
          case ratings[a.grade] do
            nil -> ""
            meaning -> ": #{meaning}"
          end

        "- Rating **#{a.rating}** for reading #{a.position}#{meaning}."
      end

    factors =
      for a <- entry.alternatives, a.factors != [] do
        "- Factors cited for reading #{a.position}: #{Enum.join(a.factors, ", ")}."
      end

    remark = if Format.present?(entry.remark), do: ["- Remark: #{entry.remark}"], else: []

    suggestion =
      if Format.present?(entry.suggestion),
        do: ["- Suggestion for translators: #{entry.suggestion}"],
        else: []

    rated = if rated == [], do: ["- No reading rated in this entry."], else: rated

    [
      "",
      "**The HOTTP committee's judgment** (its conclusion, not manuscript evidence):"
    ] ++ rated ++ factors ++ remark ++ suggestion
  end

  # Each factor the entries cite, once, from the report's introduction.
  defp factor_lines(entries, factors) do
    cited =
      entries
      |> Enum.flat_map(& &1.alternatives)
      |> Enum.flat_map(& &1.factors)
      |> Enum.map(&factor_number/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    explained =
      for number <- cited do
        case factors[number] do
          nil ->
            "- **Factor #{number}:** not explained in the report's introduction."

          f ->
            "- **Factor #{number}, #{f.name}** (#{String.downcase(f.kind)}): #{excerpt(f.explanation)}"
        end
      end

    if explained == [],
      do: [],
      else: [
        "### The factors cited, as the report's introduction explains them",
        "*The committee lists after a reading some, not all, of the factors that decided it for " <>
          "or against that reading, most important first.*"
        | explained
      ]
  end

  # '12 (for/pour …)', '7(?)' → 12, 7.
  defp factor_number(text) do
    case Integer.parse(text) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  # The explanation's first two sentences (the full text is linked).
  defp excerpt(text) do
    sentences = String.split(text, ". ")

    case Enum.split(sentences, 2) do
      {kept, []} -> Enum.join(kept, ". ")
      {kept, _more} -> Enum.join(kept, ". ") <> ". …"
    end
  end

  defp hottp_citations(entry, %{witness_sources: %{"hottp" => source}} = result) do
    [Citations.hottp(entry.id, entry.reference, source.source_url)] ++
      if(Enum.any?(entry.alternatives, &Format.present?(&1.rating)),
        do: [Citations.hottp_glossary(:ratings, source.source_url)],
        else: []
      ) ++
      if(Enum.any?(entry.alternatives, &(&1.factors != [])) and result.glossary.factors != %{},
        do: [Citations.hottp_glossary(:factors, source.source_url)],
        else: []
      )
  end

  defp hottp_citations(_entry, _result), do: []

  # --- The SBLGNT apparatus ---------------------------------------------------

  defp apparatus_lines(%{apparatus: []}), do: []

  defp apparatus_lines(%{apparatus: units} = result) do
    sigla =
      units
      |> Enum.flat_map(&(&1.lemma_sigla ++ Enum.flat_map(&1.variants, fn v -> v.sigla end)))
      |> Enum.uniq()
      |> Enum.map(&{&1, Witnesses.siglum(&1)})
      |> Enum.reject(fn {_, meaning} -> is_nil(meaning) end)

    [
      "## SBLGNT apparatus at #{hd(units).reference}",
      "*Which printed editions read what, not manuscripts: at each variation unit the SBL " <>
        "Greek New Testament's reading comes first, with the editions that agree, then each " <>
        "variant with the editions that print it. '+' adds the words, '–' omits them.*",
      ""
    ] ++
      Enum.flat_map(units, &unit_lines(&1, result)) ++
      if(sigla == [],
        do: [],
        else: ["**Editions:** " <> Enum.map_join(sigla, "; ", fn {s, m} -> "#{s}: #{m}" end)]
      ) ++ ["", "---", ""]
  end

  defp unit_lines(%{parsed: false} = unit, result) do
    [
      "### Variation unit #{unit.unit}",
      "- The note as the apparatus gives it (not split into readings): `#{String.trim(unit.note)}`"
    ] ++ source_lines([apparatus_citation(unit, result)]) ++ [""]
  end

  defp unit_lines(unit, result) do
    span = if unit.verses, do: " (verses #{unit.verses})", else: ""

    [
      "### Variation unit #{unit.unit}#{span}",
      "- **SBLGNT:** #{unit.lemma} — #{Enum.join(unit.lemma_sigla, ", ")}"
    ] ++
      Enum.map(unit.variants, fn v ->
        "- **Variant:** #{variant_text(v.text)} — #{Enum.join(v.sigla, ", ")}"
      end) ++ source_lines([apparatus_citation(unit, result)]) ++ [""]
  end

  defp variant_text(""), do: "(the same words, in Westcott and Hort's double brackets)"
  defp variant_text(text), do: text

  defp apparatus_citation(unit, %{witness_sources: %{"sblgnt_apparatus" => source}}),
    do: Citations.sblgnt_apparatus(unit.reference, unit.file, unit.line, source.source_url)
end
