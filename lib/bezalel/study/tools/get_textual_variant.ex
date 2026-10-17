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
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Patterns, Reference}

  # Cases that record how agreed text is read, not a manuscript variant.
  @interpretive_case_keys ["MT_preserved", "translation_choice"]

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
    with {:ok, result} <- result(args), do: {:ok, render(result)}
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
          tradition: String.t() | nil
        }

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
            %{translation: String.t(), preferred_reading: String.t(), rationale: String.t() | nil}
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

  @type t :: %{reference: String.t(), cases: [variant_case()], quotations: [quotation()]}

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
        DB.with_pack(:notes, &record(&1, reference, normalized))
    end
  end

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
        |> Enum.map(
          &%{
            translation: &1["translation"],
            preferred_reading: &1["preferred_reading"],
            rationale: &1["rationale"]
          }
        )
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

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{reference: reference, cases: [], quotations: []}) do
    "No textual-variant case or NT quotation alignment is catalogued for #{reference}."
  end

  def render(%{reference: reference, cases: cases, quotations: quotations}) do
    {interpretive, variants} = Enum.split_with(cases, &(&1.kind == :interpretive))

    title =
      if cases != [] and variants == [],
        do: "# Translation and interpretation notes for #{reference}",
        else: "# Textual variant record for #{reference}"

    shown =
      Enum.reduce(variants, %{}, fn c, acc ->
        readings = MapSet.new(c.readings, &{&1.text, &1.original_text})
        Map.update(acc, c.reference, readings, &MapSet.union(&1, readings))
      end)

    lines =
      [title, ""] ++
        Enum.flat_map(variants, &variant_lines/1) ++
        Enum.flat_map(interpretive, &interpretive_lines(&1, shown[&1.reference])) ++
        quotation_lines(quotations)

    lines |> Enum.join("\n") |> String.trim_trailing()
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

    texts =
      for reading <- c.readings,
          not MapSet.member?(shown || MapSet.new(), {reading.text, reading.original_text}),
          line <- text_lines(reading),
          do: line

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
    ["\n**Witnesses agreeing with this text:** " <> Enum.map_join(witnesses, ", ", &dated/1)]
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

    [line] ++ source_lines(w)
  end

  defp source_lines(item) do
    if(Format.present?(item.citation), do: ["  - Citation: #{item.citation}"], else: []) ++
      if Format.present?(item.url), do: ["  - Source: #{item.url}"], else: []
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
          if Format.present?(d.rationale), do: ["  - Rationale: #{d.rationale}"], else: []
      end) ++
      section(c.author_claims, "### Author-specific claims", fn claim ->
        ["- **#{claim.attribution}.** #{claim.text}" | source_lines(claim)]
      end) ++
      section(c.theological_interpretations, "### Theological interpretations", &sourced/1)
  end

  defp section([], _heading, _lines), do: []
  defp section(items, heading, lines), do: ["", heading | Enum.flat_map(items, lines)]

  defp sourced(item) do
    attribution = if Format.present?(item.attribution), do: item.attribution, else: "Unattributed"
    ["- **Attribution: #{attribution}.** #{item.text}" | source_lines(item)]
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
end
