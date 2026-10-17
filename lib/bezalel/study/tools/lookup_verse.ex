defmodule Bezalel.Study.Tools.LookupVerse do
  @moduledoc """
  `lookup_verse`: a verse, range or chapter in English (BSB) and in Hebrew
  or Greek, word by word with Strong's numbers.

  Ported from studybible-mcp's `handle_lookup_verse` (MIT). Same text,
  hints included: Torah weave partners (core pack), catalogued textual
  variants or translation notes and NT↔OT quotations in the passage (notes
  pack; left out silently when that pack isn't on the device). The
  cross-reference hint names only the TSK, the one cross-reference set in
  the core pack.

  `result/1` returns the passage as data (`t:Bezalel.Study.Format.verse_view/0`
  rows: each word with its Strong's number) for the passage card, with the
  hints as data.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Hermeneutics, Reference, Verses}
  alias Bezalel.Study.Tools.GetTextualVariant

  @torah ~w(Gen Exo Lev Num Deu)
  # Upper bound on verses per call; longer passages (Psalm 119) are cut with
  # a note naming the continuation.
  @max_verses 50

  @forms "a verse ('John 3:16'), a verse range ('Luke 19:1-3'), a cross-chapter " <>
           "range ('Luke 19:45-20:2'), or a whole chapter ('Psalm 23')"

  @impl true
  def name, do: "lookup_verse"

  @impl true
  def description do
    """
    Look up the text of a Bible verse, verse range, or whole chapter, in English and in the original language.

    Returns, for each verse in canonical order:
    - The English text: the Berean Standard Bible (BSB), or STEPBible's word
      gloss marked [gloss] where the BSB lacks the verse
    - The original Greek/Hebrew text (optional, on by default)
    - A word-by-word breakdown with Strong's numbers and glosses (single verses;
      for a passage only when include_morphology is set)
    - Optional grammatical parsing for each word

    And once for the passage:
    - Genre-specific interpretive background for the passage's literary type
    - Availability notes for related data (cross-references, Torah weave partners,
      and NT/OT LXX-quotation variants) where the verses have such records

    Accepts 'John 3:16', 'Luke 19:1-3', cross-chapter ranges such as
    'Luke 19:45-20:2', and whole chapters such as 'Psalm 23'. Single-chapter books
    may be cited by verse alone ('Jude 3', 'Philemon 6', '3 John 4'); 'Jude 1' is the
    whole chapter. Numbering is English; a Psalm superscription (verse 1 in the
    Hebrew) is labelled as the superscription. Returns at most #{@max_verses} verses per
    call, with a note naming the reference that continues a longer passage.

    Relevant whenever the verified wording of a passage, or its original-language
    form, is needed.\
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
            "Bible reference (e.g., 'John 3:16', 'Luke 19:1-3', 'Luke 19:45-20:2', or a whole chapter such as 'Psalm 23')"
        },
        "include_original" => %{
          "type" => "boolean",
          "description" => "Include original Greek/Hebrew text. Default: true"
        },
        "include_morphology" => %{
          "type" => "boolean",
          "description" =>
            "Include grammatical parsing for each word (and, for a passage, the word-by-word list). Default: false"
        }
      },
      "required" => ["reference"]
    }
  end

  @doc "The Markdown for the model, with `result/1`'s data for the screens (rho's tool details)."
  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, {:details, render(result), result}}
  end

  @typedoc """
  A catalogued textual-variant (or, `interpretive_cases`, translation and
  interpretation notes) case in the passage, `reference` as 'Psalm 40:6'.
  """
  @type case_cue :: %{
          reference: String.t(),
          chapter: integer(),
          verse: integer(),
          case_key: String.t()
        }

  @typedoc """
  What the hints point to: whether Torah weave data covers the book, the
  variant and interpretive cases in the passage, and the NT↔OT quotations
  with a verse in it (`side`: which side of the quotation is in it).
  """
  @type hints :: %{
          torah_weave: boolean(),
          variant_cases: [case_cue()],
          interpretive_cases: [case_cue()],
          quotations: [map()]
        }

  @typedoc """
  A looked-up passage. `label` is the heading of a passage (nil for a
  single verse), `notes` say how the request was cut, `hint_reference` is
  the verse other tools are pointed at.
  """
  @type t :: %{
          reference: String.t(),
          book: String.t(),
          book_name: String.t(),
          single: boolean(),
          label: String.t() | nil,
          notes: [String.t()],
          genre: Hermeneutics.genre() | nil,
          hint_reference: String.t(),
          hints: hints(),
          include_original: boolean(),
          include_morphology: boolean(),
          verses: [Format.verse_view()]
        }

  @doc """
  The passage `args` name, as data, or `{:error, message}` for a reference
  the pack can't serve (unreadable, unknown book, chapter or verse).
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    with {:ok, found} <- find(Args.reference(args)) do
      {:ok,
       Map.merge(found, %{
         include_original: Args.flag(args, "include_original", true),
         include_morphology: Args.flag(args, "include_morphology", false)
       })}
    end
  end

  defp find(""), do: {:error, "Please provide a verse reference (e.g., 'John 3:16')."}

  defp find(reference) do
    case Reference.parse_passage(reference) do
      nil ->
        {:error,
         "Could not read '#{reference}' as a Bible reference. Supported forms: #{@forms}."}

      parsed ->
        with {:ok, found} <- DB.with_pack(:core, &fetch(&1, reference, parsed)),
             {:ok, found} <- found do
          {:ok, add_notes_hints(found)}
        end
    end
  end

  defp fetch(conn, reference, parsed) do
    %{book: book, book_name: book_name, start_chapter: sc, end_chapter: ec} = parsed
    bounds = Verses.chapter_bounds(conn, book)

    with :ok <- check_book(bounds, book_name, reference),
         :ok <- check_chapter(bounds, book_name, sc),
         :ok <- check_chapter(bounds, book_name, ec),
         sv = parsed.start_verse || elem(bounds[sc], 0),
         ev = parsed.end_verse || elem(bounds[ec], 1),
         :ok <- check_start(bounds, book_name, sc, sv),
         :ok <- check_order({sc, sv}, {ec, ev}, reference) do
      {ev, notes} = clamp(bounds, book_name, ec, ev)

      case Verses.passage(conn, book, sc, sv, ec, ev) do
        [] -> {:error, "No verse text on file for #{reference}."}
        rows -> {:ok, shape(rows, reference, parsed, notes, torah_weave?(conn, book))}
      end
    end
  end

  defp check_book(bounds, book_name, reference) when map_size(bounds) == 0,
    do:
      {:error,
       "Unknown book '#{book_name}' in '#{reference}'. Use a book name or " <>
         "abbreviation such as 'John', 'Gen', or '1 Corinthians'."}

  defp check_book(_bounds, _book_name, _reference), do: :ok

  defp check_chapter(bounds, book_name, chapter) do
    if Map.has_key?(bounds, chapter),
      do: :ok,
      else:
        {:error,
         "#{book_name} has no chapter #{chapter} " <>
           "(chapters #{Enum.min(Map.keys(bounds))}–#{Enum.max(Map.keys(bounds))})."}
  end

  defp check_start(bounds, book_name, chapter, verse) do
    {first, last} = bounds[chapter]

    if first <= verse and verse <= last,
      do: :ok,
      else: {:error, "#{book_name} #{chapter} has no verse #{verse} (verses #{first}–#{last})."}
  end

  defp check_order(start, finish, reference) do
    if finish < start,
      do: {:error, "Invalid range '#{reference}': the end comes before the start."},
      else: :ok
  end

  defp clamp(bounds, book_name, chapter, verse) do
    {_, chapter_end} = bounds[chapter]

    if verse > chapter_end,
      do:
        {chapter_end,
         [
           "#{book_name} #{chapter} ends at verse #{chapter_end}; " <>
             "showing through #{chapter}:#{chapter_end}."
         ]},
      else: {verse, []}
  end

  # Caps the rows at @max_verses numbered verses (a verse-0 superscription
  # is shown but not counted; a verse may be several rows) and works out
  # the heading, notes and hint reference.
  defp shape(rows, reference, parsed, notes, torah_weave) do
    keys = rows |> Enum.map(&{&1["chapter"], &1["verse"]}) |> Enum.uniq()
    {rows, keys, notes} = cap(rows, keys, parsed.book_name, notes)
    shown_end = List.last(keys)
    single = hd(keys) == shown_end

    shown_start =
      case keys do
        [{_, 0}, next | _] -> next
        [first | _] -> first
      end

    plain = single and notes == []
    first_numbered = Enum.find(keys, shown_start, fn {_, verse} -> verse > 0 end)

    %{
      reference: reference,
      book: parsed.book,
      book_name: parsed.book_name,
      single: single,
      label: if(plain, do: nil, else: label(parsed, notes, shown_start, shown_end)),
      notes: notes,
      genre: Hermeneutics.genre(parsed.book),
      hint_reference:
        if(plain,
          do: reference,
          else: Reference.label(parsed.book_name, first_numbered, first_numbered)
        ),
      hints: %{
        torah_weave: torah_weave,
        variant_cases: [],
        interpretive_cases: [],
        quotations: []
      },
      span: {shown_start, shown_end},
      verses: Enum.map(rows, &Format.verse_view/1)
    }
  end

  defp torah_weave?(conn, book),
    do: book in @torah and DB.one(conn, "SELECT 1 AS x FROM torah_weave_units LIMIT 1") != nil

  # The textual-variant and quotation hints, from the notes pack when it's
  # on the device (else none).
  defp add_notes_hints(%{span: span} = found) do
    found = Map.delete(found, :span)

    case DB.with_pack(:notes, &notes_hints(&1, found, span)) do
      {:ok, hints} -> %{found | hints: Map.merge(found.hints, hints)}
      {:error, _} -> found
    end
  end

  defp notes_hints(conn, found, {{sc, sv}, {ec, ev}}) do
    cases =
      conn
      |> DB.all(
        """
        SELECT chapter, verse, case_key FROM textual_variant_cases
        WHERE book = ? AND chapter * 1000 + verse BETWEEN ? AND ?
        ORDER BY chapter, verse, id
        """,
        [found.book, sc * 1000 + sv, ec * 1000 + ev]
      )
      |> Enum.map(fn row ->
        position = {row["chapter"], row["verse"]}

        %{
          reference: Reference.label(found.book_name, position, position),
          chapter: row["chapter"],
          verse: row["verse"],
          case_key: row["case_key"]
        }
      end)

    # A verse with a variant is cued once, as a variant: get_textual_variant
    # returns its interpretation notes with it.
    {interpretive, variants} =
      Enum.split_with(cases, &GetTextualVariant.interpretive?(&1.case_key))

    variant_verses = MapSet.new(variants, &{&1.chapter, &1.verse})

    %{
      variant_cases: variants,
      interpretive_cases:
        Enum.reject(interpretive, &MapSet.member?(variant_verses, {&1.chapter, &1.verse})),
      quotations: quotations(conn, found.book, {sc, sv}, {ec, ev})
    }
  end

  # The NT↔OT quotations whose OT (else NT) verse lies in the passage.
  defp quotations(conn, book, first, last) do
    for row <-
          DB.all(
            conn,
            "SELECT * FROM nt_ot_lxx_quote_hints WHERE nt_book = ? OR ot_book = ? ORDER BY id",
            [book, book]
          ),
        side = Enum.find([:ot, :nt], &in_passage?(row["#{&1}_reference"], book, first, last)) do
      row |> GetTextualVariant.quotation() |> Map.put(:side, side)
    end
  end

  defp in_passage?(reference, book, first, last) do
    with [^book, chapter, verse | _] <- String.split(reference, "."),
         {chapter, ""} <- Integer.parse(chapter),
         {verse, ""} <- Integer.parse(verse) do
      first <= {chapter, verse} and {chapter, verse} <= last
    else
      _ -> false
    end
  end

  defp cap(rows, keys, book_name, notes) do
    numbered = Enum.filter(keys, fn {_, verse} -> verse > 0 end)

    case Enum.split(numbered, @max_verses) do
      {_, []} ->
        {rows, keys, notes}

      {shown, [next | _]} ->
        last_shown = List.last(shown)
        rest = Reference.label(book_name, next, List.last(numbered))

        note =
          "Showing the first #{@max_verses} of #{length(numbered)} verses. " <>
            "Continue with reference='#{rest}'."

        {Enum.filter(rows, &({&1["chapter"], &1["verse"]} <= last_shown)),
         Enum.filter(keys, &(&1 <= last_shown)), notes ++ [note]}
    end
  end

  # A passage's heading: the chapter(s) when whole chapters were asked for
  # and shown in full, else the span shown.
  defp label(%{start_verse: nil, end_verse: nil} = parsed, [], _start, _end) do
    if parsed.end_chapter == parsed.start_chapter,
      do: "#{parsed.book_name} #{parsed.start_chapter}",
      else: "#{parsed.book_name} #{parsed.start_chapter}-#{parsed.end_chapter}"
  end

  defp label(parsed, _notes, shown_start, shown_end),
    do: Reference.label(parsed.book_name, shown_start, shown_end)

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(result) do
    plain = result.single and result.notes == []
    bsb = Format.bsb_label(result.verses)

    verse_text =
      result.verses
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {view, index} ->
        Format.verse(view,
          include_original: result.include_original,
          include_morphology: result.include_morphology,
          include_words: result.single or result.include_morphology,
          heading_note: if(plain and index == 0, do: bsb, else: "")
        )
      end)

    text =
      if plain do
        verse_text
      else
        notes =
          if result.notes == [],
            do: "",
            else: Enum.map_join(result.notes, &"*#{&1}*\n") <> "\n"

        "# #{result.label}#{bsb}\n\n" <> notes <> verse_text
      end

    text <>
      genre(result.genre) <>
      torah_weave_hint(result) <>
      variant_hints(result) <>
      quotation_hint(result) <> cross_reference_hint(result.single, result.hint_reference)
  end

  defp genre(nil), do: ""
  defp genre(genre), do: "\n\n---\n" <> Hermeneutics.format_guidance(genre)

  defp torah_weave_hint(%{hints: %{torah_weave: false}}), do: ""

  defp torah_weave_hint(%{single: true, hint_reference: hint}) do
    "\n\n---\n*Torah Weave structural partners available for this verse " <>
      "via `get_torah_weave` (reference='#{hint}') — returns the cells " <>
      "this verse is deliberately paired with under Moshe Kline's Woven " <>
      "Torah hypothesis.*"
  end

  defp torah_weave_hint(%{hint_reference: hint}) do
    "\n\n---\n*Torah Weave structural partners are available per verse " <>
      "via `get_torah_weave` (e.g. reference='#{hint}') — returns " <>
      "the cells a verse is deliberately paired with under Moshe Kline's " <>
      "Woven Torah hypothesis.*"
  end

  defp variant_hints(%{single: true, hint_reference: hint, hints: hints}) do
    cond do
      hints.variant_cases != [] ->
        "\n\n---\n*Textual variant catalogued for this verse " <>
          "(#{Enum.map_join(hints.variant_cases, ", ", & &1.case_key)}): " <>
          "readings, witnesses, and attributed analysis via " <>
          "`get_textual_variant` (reference='#{hint}').*"

      hints.interpretive_cases != [] ->
        "\n\n---\n*Translation and interpretation notes catalogued for this " <>
          "verse (no manuscript variant): translation decisions and attributed " <>
          "analysis via `get_textual_variant` (reference='#{hint}').*"

      true ->
        ""
    end
  end

  defp variant_hints(%{hints: hints}) do
    variants =
      if hints.variant_cases == [],
        do: "",
        else:
          "\n\n---\n*Textual variants catalogued in this passage: #{cued(hints.variant_cases)}. " <>
            "Readings, witnesses, and attributed analysis via " <>
            "`get_textual_variant` with one of those verses as the reference.*"

    interpretive =
      if hints.interpretive_cases == [],
        do: "",
        else:
          "\n\n---\n*Translation and interpretation notes (no manuscript variant) " <>
            "catalogued in this passage: #{cued(hints.interpretive_cases)}. Translation " <>
            "decisions and attributed analysis via `get_textual_variant` with one " <>
            "of those verses as the reference.*"

    variants <> interpretive
  end

  defp cued(cases), do: Enum.map_join(cases, ", ", &"#{&1.reference} (#{&1.case_key})")

  # At most two quotations inline; a quotation that agrees with the MT is
  # not called an LXX form.
  defp quotation_hint(%{hints: %{quotations: []}}), do: ""

  defp quotation_hint(%{single: single, hint_reference: hint, hints: %{quotations: quotations}}) do
    {shown, rest} = Enum.split(quotations, 2)
    cues = Enum.map(shown, &quotation_cue(&1, single))
    more = if rest == [], do: [], else: ["#{length(rest)} more"]

    target =
      if single,
        do: "(reference='#{hint}')",
        else: "with the quoting or quoted verse as the reference"

    label =
      if Enum.all?(quotations, & &1.follows_lxx),
        do: "NT↔OT LXX-form quotation",
        else: "NT↔OT quotation"

    "\n\n---\n*#{label}: " <>
      Enum.join(cues ++ more, "; ") <>
      ". Separated manuscript evidence and attributed analysis via " <>
      "`get_textual_variant` #{target}.*"
  end

  defp quotation_cue(q, single) do
    {cue, own} =
      case q.side do
        :ot -> {"quoted in **#{q.nt_display}** (#{q.divergence_type})", q.ot_display}
        :nt -> {"quotes **#{q.ot_display}**#{lxx_form(q)} (#{q.divergence_type})", q.nt_display}
      end

    if single, do: cue, else: "#{own} #{cue}"
  end

  defp lxx_form(%{follows_lxx: true}), do: " in its LXX form"
  defp lxx_form(_), do: ""

  defp cross_reference_hint(true, hint) do
    "\n\n---\n*Cross-references for this verse are available via " <>
      "`get_cross_references` (reference='#{hint}') — returns the strongest verses " <>
      "traditionally read alongside this one in the Treasury of Scripture " <>
      "Knowledge (TSK) topical index.*"
  end

  defp cross_reference_hint(false, hint) do
    "\n\n---\n*Cross-references are indexed per verse: call `get_cross_references` " <>
      "with one verse of this passage (e.g. reference='#{hint}') — returns the " <>
      "strongest verses traditionally read alongside it in the Treasury of " <>
      "Scripture Knowledge (TSK) topical index.*"
  end
end
