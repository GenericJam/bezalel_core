defmodule Bezalel.Study.Tools.LookupVerse do
  @moduledoc """
  `lookup_verse`: a verse, range or chapter in English (the user's
  translation: the NET or the BSB) and in Hebrew or Greek, word by word with
  Strong's numbers (STEPBible's).

  Ported from studybible-mcp's `handle_lookup_verse` (MIT). Same text,
  hints included: Torah weave partners (core pack), catalogued textual
  variants or translation notes and NT↔OT quotations in the passage (notes
  pack; left out silently when that pack isn't on the device), and, added
  for Bezalel, the verses with HOTTP entries or SBLGNT apparatus units
  (witnesses pack, likewise silent without it). The
  cross-reference hint names only the TSK, the one cross-reference set in
  the core pack. The user's preferences (`Bezalel.Study.Preferences`) pick
  the translation and can switch off the genre guidance and the Torah
  weave hint (`Bezalel.Study.Sources`).

  `result/1` returns the passage as data (`t:Bezalel.Study.Format.verse_view/0`
  rows: each word with its Strong's number) for the passage card, with the
  hints and the translation (`translation`: key, abbreviation, link) as data.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{
    Args,
    Citation,
    Citations,
    DB,
    Format,
    Hermeneutics,
    Preferences,
    Reference,
    Sources,
    Translations,
    Verses,
    Witnesses
  }

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
    - The English text in the user's chosen translation (NET or BSB), labelled with
      its abbreviation, or STEPBible's word gloss marked [gloss] where it lacks the verse
    - The original Greek/Hebrew text (optional, on by default)
    - A word-by-word breakdown with Strong's numbers and glosses (single verses;
      for a passage only when include_morphology is set)
    - Optional grammatical parsing for each word

    And once for the passage:
    - Genre-specific interpretive background for the passage's literary type (when
      the user has turned it on)
    - Availability notes for related data (cross-references, Torah weave partners,
      NT/OT LXX-quotation variants, and text-critical notes: the UBS HOTTP committee's
      entries and the SBLGNT apparatus) where the verses have such records

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
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)),
         do: Citations.details(render(result), result, citations(result))
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
  variant and interpretive cases in the passage, the NT↔OT quotations
  with a verse in it (`side`: which side of the quotation is in it), and
  the verses with HOTTP entries or SBLGNT apparatus units in the
  witnesses pack (`witnesses`, 'Gen.4.8'; none without the pack).
  """
  @type hints :: %{
          torah_weave: boolean(),
          variant_cases: [case_cue()],
          interpretive_cases: [case_cue()],
          quotations: [map()],
          witnesses: %{hottp: [String.t()], apparatus: [String.t()]}
        }

  @typedoc """
  A looked-up passage. `label` is the heading of a passage (nil for a
  single verse), `notes` say how the request was cut, `hint_reference` is
  the verse other tools are pointed at. `translation` is the English
  quoted (an app draws its label and link from it), `translation_note` says
  why it isn't the one the user chose (nil when it is), `genre_guidance`
  whether the genre guidance is shown.
  """
  @type t :: %{
          reference: String.t(),
          book: String.t(),
          book_name: String.t(),
          single: boolean(),
          label: String.t() | nil,
          notes: [String.t()],
          genre: Hermeneutics.genre() | nil,
          genre_guidance: boolean(),
          hint_reference: String.t(),
          hints: hints(),
          include_original: boolean(),
          include_morphology: boolean(),
          translation: Translations.ref(),
          translation_note: String.t() | nil,
          verses: [Format.verse_view()]
        }

  @doc """
  The passage `args` name, as data, under the host's current preferences
  (`result/2`).
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc """
  The passage `args` name, as data, in `prefs`' translation, or `{:error,
  message}` for a reference the pack can't serve (unreadable, unknown book,
  chapter or verse).
  """
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    with {:ok, found} <- find(Args.reference(args), prefs) do
      {:ok,
       Map.merge(found, %{
         include_original: Args.flag(args, "include_original", true),
         include_morphology: Args.flag(args, "include_morphology", false)
       })}
    end
  end

  defp find("", _prefs), do: {:error, "Please provide a verse reference (e.g., 'John 3:16')."}

  defp find(reference, prefs) do
    case Reference.parse_passage(reference) do
      nil ->
        {:error,
         "Could not read '#{reference}' as a Bible reference. Supported forms: #{@forms}."}

      parsed ->
        Translations.with_translation(
          prefs.translation,
          &passage(reference, parsed, prefs, &1, &2)
        )
    end
  end

  # The passage in `translation`, with its hints and the preferences' parts.
  defp passage(reference, parsed, prefs, translation, note) do
    with {:ok, found} <- DB.with_pack(:core, &fetch(&1, reference, parsed, translation)),
         {:ok, found} <- found do
      {:ok,
       found
       |> add_witness_hints()
       |> add_notes_hints()
       |> Map.merge(%{
         translation: Translations.ref(translation),
         translation_note: note,
         genre_guidance: Sources.enabled?(prefs, "method:genre_guidance")
       })
       |> update_in([:hints, :torah_weave], &(&1 and torah_weave_on?(prefs)))}
    end
  end

  defp torah_weave_on?(prefs), do: Sources.enabled?(prefs, "method:torah_weave")

  defp fetch(conn, reference, parsed, translation) do
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

      case Verses.passage(conn, book, {sc, sv}, {ec, ev}, translation) do
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
        quotations: [],
        witnesses: %{hottp: [], apparatus: []}
      },
      span: {shown_start, shown_end},
      verses: Enum.map(rows, &Format.verse_view/1)
    }
  end

  defp torah_weave?(conn, book),
    do: book in @torah and DB.one(conn, "SELECT 1 AS x FROM torah_weave_units LIMIT 1") != nil

  # The verses with HOTTP entries or SBLGNT apparatus units, from the
  # witnesses pack when it's on the device and readable (else none).
  defp add_witness_hints(%{span: {{sc, sv}, {ec, ev}}} = found) do
    read = fn conn ->
      with :ok <- Witnesses.check(conn, ["hottp_verses", "sblgnt_apparatus"]),
           do: {:ok, Witnesses.hints(conn, found.book, sc * 1000 + sv, ec * 1000 + ev)}
    end

    case DB.with_pack(:witnesses, read) do
      {:ok, {:ok, hints}} -> put_in(found, [:hints, :witnesses], hints)
      _missing -> found
    end
  end

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
    label = Format.translation_label(result.verses, result.translation)

    verse_text =
      result.verses
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {view, index} ->
        Format.verse(view,
          include_original: result.include_original,
          include_morphology: result.include_morphology,
          include_words: result.single or result.include_morphology,
          heading_note: if(plain and index == 0, do: label, else: "")
        ) <> source(verse_citations(view, result))
      end)

    text =
      if plain do
        verse_text
      else
        notes =
          if result.notes == [],
            do: "",
            else: Enum.map_join(result.notes, &"*#{&1}*\n") <> "\n"

        "# #{result.label}#{label}\n\n" <> notes <> verse_text
      end

    Format.translation_note(result.translation_note) <>
      text <>
      genre(result.genre_guidance && result.genre) <>
      torah_weave_hint(result) <>
      variant_hints(result) <>
      witness_hint(result) <>
      quotation_hint(result) <> cross_reference_hint(result.single, result.hint_reference)
  end

  defp genre(nil), do: ""
  defp genre(false), do: ""

  defp genre(genre) do
    "\n\n---\nGenre guidance after Fee & Stuart, *How to Read the Bible for All Its Worth* " <>
      "(evangelical):\n\n" <>
      Hermeneutics.format_guidance(genre) <> "\n\n" <> Citation.source_line(genre_citation(genre))
  end

  @doc """
  The sources `render/1` shows, in its order (a `Source:` line under each
  verse): each verse in the quoted translation (unless only STEPBible's
  gloss stands in for it) and its original on STEP Bible, then Fee &
  Stuart when the genre guidance is shown.
  """
  @spec citations(t()) :: [Citation.t()]
  def citations(result) do
    Enum.flat_map(result.verses, &verse_citations(&1, result)) ++
      if(result.genre_guidance && result.genre, do: [genre_citation(result.genre)], else: [])
  end

  # A verse's sources: the translation's verse page when its text is the
  # translation's, and the Hebrew or Greek on STEP when the original (or
  # STEPBible's gloss, standing in for the English) is shown.
  defp verse_citations(view, result) do
    english =
      if view.translated, do: [Citations.scripture(view.reference, result.translation)], else: []

    original =
      if result.include_original or not view.translated,
        do: [Citations.step(view.reference)],
        else: []

    english ++ original
  end

  defp genre_citation(genre) do
    name =
      case List.keyfind(Hermeneutics.guidelines(), genre, 0) do
        {_, %{name: name}} -> name
        nil -> genre
      end

    Citations.fee_stuart(name)
  end

  defp source([]), do: ""
  defp source(citations), do: Citation.source_line(citations) <> "\n"

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

  # Where get_textual_variant has the HOTTP committee's entries or the
  # SBLGNT apparatus: the verse, or up to ten verses of a passage.
  defp witness_hint(%{hints: %{witnesses: %{hottp: [], apparatus: []}}}), do: ""

  defp witness_hint(%{single: true, hint_reference: hint, hints: %{witnesses: w}}) do
    "\n\n---\n*Text-critical notes for this verse in #{witness_kinds(w)}, via " <>
      "`get_textual_variant` (reference='#{hint}').*"
  end

  defp witness_hint(%{book_name: name, hints: %{witnesses: w}}) do
    references = Enum.uniq(w.hottp ++ w.apparatus) |> Enum.sort_by(&position/1)
    {shown, rest} = Enum.split(references, 10)

    listed =
      Enum.map(shown, fn reference ->
        position = position(reference)
        Reference.label(name, position, position)
      end) ++ if(rest == [], do: [], else: ["#{length(rest)} more"])

    "\n\n---\n*Text-critical notes in #{witness_kinds(w)} in this passage: " <>
      Enum.join(listed, ", ") <>
      ". Via `get_textual_variant` with one of those verses as the reference.*"
  end

  defp witness_kinds(%{hottp: hottp, apparatus: apparatus}) do
    [
      hottp != [] && "the UBS Hebrew Old Testament Text Project (HOTTP)",
      apparatus != [] && "the SBLGNT apparatus"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" and ")
  end

  defp position(reference) do
    [_book, chapter, verse] = String.split(reference, ".")
    {String.to_integer(chapter), String.to_integer(verse)}
  end

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
