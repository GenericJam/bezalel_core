defmodule Bezalel.Study.Tools.CompareBiblicalVersions do
  @moduledoc """
  `compare_biblical_versions`: the Masoretic Text and the Septuagint side by
  side for an Old Testament or Septuagint verse, range or chapter, each row
  with its edition's own reference and its provenance.

  Ported from studybible-mcp's `handle_compare_biblical_versions`,
  `_cap_comparison_rows`, `compare_biblical_versions`, `_fetch_mt_rows`,
  `_lxx_row` and `format_biblical_version_comparison` (MIT; constants from
  `parsers/biblical_versions.py`). Same text. The LXX rows come from the
  lxx pack and the MT rows from the core pack's `verses`, one `with_pack/2`
  each, opened only when the call needs it: an MT-only comparison in
  canonical numbering works without the lxx pack, as theirs works without
  the LXX table. Their "Septuagint comparison data is not in this database"
  message is the lxx pack error. A chapter or verse number too large for
  SQLite (theirs raised an overflow) is the unparseable-reference error.

  `result/1` returns the rows (MT and LXX, in display order) as data. Each
  row has a `Source:` line (`citations/1`): the MT's Hebrew and the LXX's
  Greek on STEP Bible, Brenton's English at eBible.org, a scroll's
  manuscript page, a Samaritan Pentateuch verse's dataset, an SBLGNT verse's
  line in its file.

  Added for Bezalel: the biblical Dead Sea Scrolls (`DSS`, the scrolls
  pack) and the Samaritan Pentateuch (`SP`, the witnesses pack, Torah
  only) as further witnesses beside the MT and LXX, each its own switchable
  source (`manuscripts:dss`, `manuscripts:sp`); a missing pack is a note,
  an error only when that witness is asked for alone. A New Testament
  reference, which theirs refused, compares the core pack's Greek (`TAGNT`:
  STEPBible's amalgamated text, every word of the major editions) with the
  SBL Greek New Testament (`SBLGNT`, the witnesses pack), grouped by the
  core pack's verse numbering, which the SBLGNT shares.

  Changed for Bezalel: their Apocrypha line ("not in the Protestant canon
  (cf. Westminster Confession 1.3); background only") is now a neutral
  line saying which traditions' canons hold each book, shown with the
  user's scripture labels on; their wording is shown, credited, only with
  the `editorial:verdicts` source (`Bezalel.Study.Sources`). A row outside
  the Hebrew Bible is marked "(not in the Hebrew Bible)", where theirs said
  "(Apocrypha)".
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{
    Ancient,
    Args,
    BiblicalScrolls,
    Citation,
    Citations,
    DB,
    Format,
    Patterns,
    Preferences,
    Sources,
    Witnesses
  }

  @max_verses 10
  @ot_versions ["MT", "LXX", "DSS", "SP"]
  @nt_versions ["TAGNT", "SBLGNT"]
  @versions @ot_versions ++ @nt_versions
  @dss_source "manuscripts:dss"
  @sp_source "manuscripts:sp"
  @torah ~w(Gen Exo Lev Num Deu)

  @nt_books ~w(Mat Mrk Luk Jhn Act Rom 1Co 2Co Gal Eph Php Col 1Th 2Th 1Ti 2Ti Tit Phm Heb Jas
               1Pe 2Pe 1Jn 2Jn 3Jn Jud Rev)
  @mt_books ~w(Gen Exo Lev Num Deu Jos Jdg Rut 1Sa 2Sa 1Ki 2Ki 1Ch 2Ch Ezr Neh Est Job Psa Pro
               Ecc Sng Isa Jer Lam Ezk Dan Hos Jol Amo Oba Jon Mic Nam Hab Zep Hag Zec Mal)
  @lxx_only_books ~w(1Es 2Es 1Ma 2Ma 3Ma 4Ma Bar Bel EsG Lje Ode Pss Sir Sus Tob Jdt Wis)

  @mt_edition "STEPBible TAHOT / Westminster Leningrad Codex"
  @mt_license "CC BY 4.0"
  @mt_source_url "https://github.com/STEPBible/STEPBible-Data"
  @mt_translation_label "STEPBible word glosses (interlinear, not a translation)"
  @mt_versification "TAHOT English/Hebrew versification"

  @tagnt_edition "STEPBible TAGNT (Translators Amalgamated Greek NT)"
  @tagnt_note "an amalgamated text: every word found in the major editions (NA27/28, SBL, " <>
                "Tyndale House, Byzantine, Textus Receptus, Westcott–Hort, Tregelles) in one " <>
                "verse, so it can hold words any one edition omits; it is no single edition's text"
  @sblgnt_edition "SBL Greek New Testament"
  @sp_edition "Samaritan Pentateuch"

  @lxx_source_url "https://github.com/OpenScriptorium/lxx-morph/tree/c91f6b1e8fb3ba37df701e6ae31f675ace71a2b2"
  @lxx_license "CC BY 4.0 (morphology); Rahlfs Greek text public domain; " <>
                 "Brenton translation and Greek text public domain"
  @lxx_translation_label "Brenton English Septuagint translation"
  @brenton_greek_source_url "https://ebible.org/details.php?id=grcbrent"
  @brenton_note "Brenton (1844) translated his own Greek edition, which is based chiefly on Codex " <>
                  "Vaticanus and is not the Rahlfs text shown, and his English sometimes departs even " <>
                  "from that Greek, so his wording may not match the Greek beside it."
  @kjv_books ~w(1Es 1Ma 2Ma Bar Bel Jdt Lje Sir Sus Tob Wis)
  @kjv_label "KJV (Authorized Version) Apocrypha, lightly adapted by Brenton"
  @kjv_note "Brenton's edition prints it in place of his own translation. The KJV was translated " <>
              "from other Greek texts, not the Rahlfs or Brenton's Greek shown, so it can add or " <>
              "omit words that Greek lacks (e.g. Sirach 17:17)."
  @verse_mapping_credit "MT/LXX verse pairs from OpenScriptorium lxx-morph, derived in part from TVTMS " <>
                          "(Tyndale Versification Traditions Mapping System), CC BY 4.0, created by " <>
                          "STEPBible.org / Tyndale House Cambridge"
  @lxx_morphology_fields ~w(surface lemma parsing pos confidence source)

  @apocrypha_books %{
    "1Es" => "1 Esdras",
    "1Ma" => "1 Maccabees",
    "2Ma" => "2 Maccabees",
    "3Ma" => "3 Maccabees",
    "4Ma" => "4 Maccabees",
    "Bar" => "Baruch",
    "Bel" => "Bel and the Dragon",
    "Jdt" => "Judith",
    "Lje" => "the Letter of Jeremiah",
    "Pss" => "the Psalms of Solomon",
    "Sir" => "Sirach",
    "Sus" => "Susanna",
    "Tob" => "Tobit",
    "Wis" => "Wisdom"
  }
  @esther_additions "the Greek additions to Esther"
  @azariah "the Prayer of Azariah and Song of the Three"
  @noncanonical_odes %{
    7 => "#{@azariah} (Odes 7–8)",
    8 => "#{@azariah} (Odes 7–8)",
    12 => "the Prayer of Manasseh (Ode 12)",
    14 => "Ode 14 (a morning hymn)"
  }
  @apocrypha_plural [
    "the Psalms of Solomon",
    @esther_additions,
    "#{@azariah} (Dan 3:24–90)",
    "#{@azariah} (Odes 7–8)"
  ]

  # Which canons hold each book or addition outside the Hebrew Bible.
  @deuterocanon [
    "1 Maccabees",
    "2 Maccabees",
    "Baruch",
    "Bel and the Dragon",
    "Judith",
    "the Letter of Jeremiah",
    "Sirach",
    "Susanna",
    "Tobit",
    "Wisdom",
    @esther_additions,
    "#{@azariah} (Dan 3:24–90)",
    "#{@azariah} (Odes 7–8)"
  ]
  @orthodox ["1 Esdras", "3 Maccabees", "Psalm 151", "the Prayer of Manasseh (Ode 12)"]
  @canons [
    {@deuterocanon, "in the Catholic and Orthodox canons, not the Jewish or Protestant ones"},
    {@orthodox, "in the Eastern Orthodox canon, not the Jewish, Catholic or Protestant ones"},
    {["4 Maccabees"], "in an appendix to Greek Orthodox Bibles, not in other canons"},
    {["the Psalms of Solomon"], "in no church's canon"}
  ]
  @outside_canons "not in the Jewish, Catholic or Protestant canons"

  @lxx_columns """
  edition, canonical_reference, canonical_book, canonical_chapter,
  canonical_verse, canonical_verse_suffix, edition_reference,
  edition_chapter, edition_verse, edition_verse_suffix,
  text, translation, morphology, mapping_method,
  brenton_greek_differs, brenton_greek, brenton_greek_difference
  """

  @impl true
  def name, do: "compare_biblical_versions"

  @impl true
  def description do
    """
    Compare the witnesses to the biblical text side by side. Old Testament or Septuagint verse, range or chapter: the Masoretic Text (MT), the Septuagint (LXX), the biblical Dead Sea Scrolls (DSS) and, for Genesis–Deuteronomy, the Samaritan Pentateuch (SP). New Testament: the Greek of the core text (TAGNT, STEPBible's amalgamated Greek NT, which holds the words of every major edition at once) and the SBL Greek New Testament (SBLGNT). Returns at most ten verses per call and names the verse to continue from.

    Rows are grouped by canonical MT/English reference and keep each edition's own reference, so Hebrew/Greek versification differences stay explicit (Psalm 82:6 = Greek Psa.81.6). MT: Westminster Leningrad Codex with STEPBible word glosses (not a translation). LXX: Rahlfs, with Brenton's English only where Brenton translated the same recension. Brenton translated his own Greek, not Rahlfs: where it differs the row warns and shows his Greek, and his English should be quoted as a rendering of that text; most Apocrypha rows carry the KJV Apocrypha instead. LXX-only verses (e.g. the Prayer of Azariah) need numbering='lxx'. DSS: every biblical scroll from Qumran and the other Judaean Desert sites that preserves the verse (Abegg–Bowley–Cook transcription, Hebrew/Aramaic, no English), each with its siglum and name (4Q37 = 4QDeutj), fragment and line, and how many letters survive outside [ ], the editors' reconstruction, which is never evidence; a verse with no DSS row survives in no scroll. Sources, licences, and the TVTMS verse-mapping credit are listed once at the end.\

    SP: the Samaritan Pentateuch's consonantal text (no vowel points or accents; MS Dublin Chester Beatty 751 and MS Garizim 1, CACCHT Text-Fabric dataset), under the English reference with the dataset's own number; a verse it groups differently says so. SBLGNT: the SBLGNT's text as printed, its ⸀ ⸂ ⸃ marking where its apparatus has a note (get_textual_variant gives the notes). None of these has English: any English is yours.
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
            "Verse, range (also across chapters), or chapter; at most 10 verses " <>
              "are returned. E.g. 'Psalm 24:1', 'Genesis 1:1-3', 'Psalm 81:6-82:1'"
        },
        "versions" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => @versions},
          "default" => @versions,
          "description" =>
            "Editions to return, in display order. Old Testament: MT, LXX, DSS (the Dead Sea " <>
              "Scrolls) and SP (the Samaritan Pentateuch, Torah only); New Testament: TAGNT " <>
              "(the core Greek) and SBLGNT. Default: all that cover the passage"
        },
        "numbering" => %{
          "type" => "string",
          "enum" => ["canonical", "lxx"],
          "default" => "canonical",
          "description" =>
            "Read the reference in canonical MT/English numbering (default) or in " <>
              "the Greek edition's numbering ('lxx', e.g. Psalm 81:6 = MT Psalm 82:6). " <>
              "Books without an MT always use Greek numbering."
        },
        "include_original" => %{
          "type" => "boolean",
          "default" => true,
          "description" => "Include Hebrew/Greek text. Default: true"
        },
        "include_morphology" => %{
          "type" => "boolean",
          "default" => false,
          "description" => "Include word-level morphology. Default: false"
        }
      },
      "required" => ["reference"]
    }
  end

  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)) do
      Citations.details(render(result), result, citations(result))
    end
  end

  @doc "The citations of the rows `render/1` shows, in its order."
  @spec citations(t()) :: [Citation.t()]
  def citations(%{rows: rows}), do: Enum.flat_map(rows, &row_citations/1)

  # MT: its Hebrew on STEP; LXX: the Rahlfs verse on STEP (by its English
  # reference) with Brenton's English where the row has it; a scroll: its
  # manuscript's page (Leon Levy has one for every manuscript the pack names).
  defp row_citations(%{version: "MT"} = row), do: [Citations.step(row.canonical_reference)]

  defp row_citations(%{version: "DSS", dss: dss}) do
    [
      Citations.dss_manuscript(dss.siglum, "#{dss.siglum} #{dss.locator}",
        leon_levy: dss.name != nil
      )
    ]
  end

  defp row_citations(%{version: "SP", sp: sp} = row),
    do: [Citations.samaritan(row.canonical_reference, sp.source_reference, sp.source_url)]

  defp row_citations(%{version: "TAGNT"} = row), do: [Citations.step(row.canonical_reference)]

  defp row_citations(%{version: "SBLGNT", sblgnt: s} = row),
    do: [Citations.sblgnt(row.canonical_reference, s.file, s.line, s.source_url)]

  defp row_citations(%{version: "LXX"} = row) do
    english = Format.present?(row.translation)

    [Citations.lxx(row.canonical_reference || row.edition_reference, english: english)] ++
      if english, do: [Citations.brenton(row.edition_reference)], else: []
  end

  @typedoc """
  A word of a row's morphology: `lemma` (LXX) or `strongs` (MT), the
  parsing (LXX) or morphology code (MT), the gloss (MT).
  """
  @type word :: %{
          surface: String.t(),
          lemma: String.t() | nil,
          strongs: String.t() | nil,
          parsing: String.t() | nil,
          pos: String.t() | nil,
          gloss: String.t() | nil
        }

  @typedoc """
  One edition's text of a verse. `canonical_reference` is nil for an
  LXX-only verse. `brenton` compares Brenton's Greek with Rahlfs (LXX rows
  with Brenton's own English): status `:same`, `:unavailable`, or
  `:differs` (then with his Greek and the difference); `:not_applicable`
  otherwise.
  """
  @type row :: %{
          version: String.t(),
          edition: String.t(),
          language: String.t(),
          canonical_reference: String.t() | nil,
          canonical_chapter: integer() | nil,
          canonical_verse: integer() | nil,
          edition_reference: String.t(),
          text: String.t(),
          translation: String.t() | nil,
          translation_label: String.t(),
          translation_note: String.t() | nil,
          license: String.t(),
          source_url: String.t(),
          mapping_method: String.t(),
          morphology: [word()],
          apocrypha: String.t() | nil,
          kjv_apocrypha: boolean(),
          brenton: brenton()
        }

  @type brenton :: %{
          status: :not_applicable | :same | :unavailable | :differs,
          greek: String.t() | nil,
          difference: String.t() | nil
        }

  @typedoc """
  A comparison. `numbering` is the one used ("lxx" for an LXX-only book);
  `lxx_only` the LXX-only verses at the requested Greek positions (for a
  canonical lookup); `cap_note` says where a cut comparison continues;
  `dss` whether the Dead Sea Scrolls witnesses were read (`:missing`: the
  scrolls pack isn't on the device), `dss_source_url` their source; `sp`
  and `sblgnt` the same for the Samaritan Pentateuch and the SBLGNT (the
  witnesses pack). No rows: nothing matched. `prefs` are the preferences
  it ran under (they decide the canon and verdict lines).
  """
  @type t :: %{
          reference: String.t(),
          versions: [String.t()],
          numbering: String.t(),
          include_original: boolean(),
          include_morphology: boolean(),
          rows: [row()],
          lxx_only: [%{edition: String.t(), edition_reference: String.t()}],
          cap_note: String.t(),
          dss: :on | :off | :missing,
          dss_source_url: String.t() | nil,
          sp: :on | :off | :missing,
          sblgnt: :on | :off | :missing,
          prefs: Preferences.t()
        }

  @doc "The rows comparing `args`' passage, under the host's current preferences."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc """
  The rows comparing `args`' passage (none when nothing matched), or
  `{:error, message}` for arguments the tool can't use, an uncovered book,
  editions of the other testament only, an MT-only request for an LXX-only
  book, or a missing pack.
  """
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    reference = Args.reference(args)

    with :ok <- present(reference),
         {:ok, requested} <- versions(Map.get(args, "versions", @versions)),
         {:ok, numbering} <- numbering(Map.get(args, "numbering", "canonical")),
         {:ok, book, start, finish} <- book(reference) do
      if book in @nt_books,
        do: nt_result(reference, {book, start, finish}, requested, args, prefs),
        else: ot_result(reference, {book, start, finish}, requested, numbering, args, prefs)
    end
  end

  defp ot_result(reference, {book, start, finish}, requested, numbering, args, prefs) do
    explicit = Map.has_key?(args, "versions")
    numbering = if(book in @lxx_only_books, do: "lxx", else: numbering)

    with {:ok, versions} <- testament(requested, @ot_versions, reference),
         {:ok, dss} <- dss_status(versions, explicit, prefs),
         versions = if(dss == :off, do: versions -- ["DSS"], else: versions),
         {:ok, sp} <- sp_status(versions, explicit, prefs, book, reference),
         versions = if(sp == :off, do: versions -- ["SP"], else: versions),
         {:ok, {rows, lxx_only, groups}} <- fetch(book, start, finish, versions, numbering),
         {:ok, dss_rows, dss, dss_url} <- dss_rows(groups, dss, {book, start, finish}, versions),
         {:ok, sp_rows, sp} <- sp_rows(groups, sp, {book, start, finish}, versions),
         rows = merge_witnesses(rows, dss_rows ++ sp_rows, groups, versions),
         :ok <- needs_lxx(rows, book, versions, reference) do
      {rows, cap_note} = cap(reference, rows, numbering)

      {:ok,
       %{
         reference: reference,
         versions: versions,
         numbering: numbering,
         include_original: Args.flag(args, "include_original", true),
         include_morphology: Args.flag(args, "include_morphology", false),
         rows: rows,
         lxx_only: lxx_only,
         cap_note: cap_note,
         dss: dss,
         dss_source_url: dss_url,
         sp: sp,
         sblgnt: :off,
         prefs: prefs
       }}
    end
  end

  # The requested editions of the passage's testament: none of them (only
  # the other testament's) is an error naming the right ones.
  defp testament(requested, editions, reference) do
    case Enum.filter(requested, &(&1 in editions)) do
      [] when editions == @ot_versions ->
        {:error,
         "#{reference} is in the Old Testament: compare MT, LXX, DSS and/or SP there " <>
           "(TAGNT and SBLGNT are New Testament editions)."}

      [] ->
        {:error,
         "#{reference} is a New Testament reference: compare TAGNT (the core Greek text) " <>
           "and/or SBLGNT there (MT, LXX, DSS and SP are Old Testament witnesses)."}

      versions ->
        {:ok, versions}
    end
  end

  # Whether the DSS witnesses are shown: `:on`; `:off` (not asked for, or
  # switched off by the user when not asked for by name); `:missing` (the
  # scrolls pack isn't on the device, said in a note). Asked for alone, a
  # switched-off source or a missing pack is the error.
  defp dss_status(versions, explicit, prefs) do
    cond do
      "DSS" not in versions -> {:ok, :off}
      not Sources.enabled?(prefs, @dss_source) and explicit -> Sources.check(prefs, @dss_source)
      not Sources.enabled?(prefs, @dss_source) -> {:ok, :off}
      DB.available?(:scrolls) -> {:ok, :on}
      versions == ["DSS"] -> {:error, DB.missing(:scrolls)}
      true -> {:ok, :missing}
    end
  end

  # Whether the Samaritan Pentateuch is shown, as `dss_status/3`: off for a
  # book outside the Torah (the error when it is asked for alone).
  defp sp_status(versions, explicit, prefs, book, reference) do
    cond do
      "SP" not in versions -> {:ok, :off}
      book not in @torah and versions == ["SP"] -> {:error, sp_torah_only(reference)}
      book not in @torah -> {:ok, :off}
      true -> sp_source_status(versions, explicit, prefs)
    end
  end

  defp sp_source_status(versions, explicit, prefs) do
    cond do
      not Sources.enabled?(prefs, @sp_source) and explicit -> Sources.check(prefs, @sp_source)
      not Sources.enabled?(prefs, @sp_source) -> {:ok, :off}
      DB.available?(:witnesses) -> {:ok, :on}
      versions == ["SP"] -> {:error, DB.missing(:witnesses)}
      true -> {:ok, :missing}
    end
  end

  defp sp_torah_only(reference),
    do:
      "The Samaritan Pentateuch has only Genesis–Deuteronomy; #{reference} isn't in it. " <>
        "Compare MT, LXX and/or DSS."

  # The DSS readings of the passage (canonical numbering: `groups` nil) or
  # of the canonical verses of the Greek passage's verse groups (`groups`:
  # `{group, canonical reference}` in order, whichever versions are shown),
  # for `merge_witnesses/4`.
  # A scrolls pack that can't be read is noted as missing (an error when
  # DSS was asked for alone).
  defp dss_rows(_groups, dss, _passage, _versions) when dss != :on,
    do: {:ok, [], dss, nil}

  defp dss_rows(groups, :on, {book, start, finish}, versions) do
    result = DB.with_pack(:scrolls, &dss_readings(&1, groups, {book, start, finish}))

    case result do
      {:ok, {:ok, dss_rows, url}} -> {:ok, dss_rows, :on, url}
      {_, {:error, message}} when versions == ["DSS"] -> {:error, message}
      {:error, message} when versions == ["DSS"] -> {:error, message}
      _damaged -> {:ok, [], :missing, nil}
    end
  end

  # The Samaritan Pentateuch's verses, as `dss_rows/4`.
  defp sp_rows(_groups, sp, _passage, _versions) when sp != :on, do: {:ok, [], sp}

  defp sp_rows(groups, :on, {book, start, finish}, versions) do
    read = fn conn ->
      with :ok <- Witnesses.check(conn, ["sp_verses"]),
           {:ok, source} <- Witnesses.source(conn, "sp") do
        {:ok, conn |> sp_verses(groups, book, start, finish) |> Enum.map(&sp_row(&1, source))}
      end
    end

    case DB.with_pack(:witnesses, read) do
      {:ok, {:ok, rows}} -> {:ok, rows, :on}
      {_, {:error, message}} when versions == ["SP"] -> {:error, message}
      {:error, message} when versions == ["SP"] -> {:error, message}
      _damaged -> {:ok, [], :missing}
    end
  end

  defp sp_verses(conn, nil, book, start, finish),
    do: Witnesses.samaritan(conn, book, verse_bound(start), verse_bound(finish))

  defp sp_verses(conn, groups, _book, _start, _finish),
    do: Witnesses.samaritan_at(conn, group_references(groups))

  defp dss_readings(conn, groups, {book, start, finish}) do
    with :ok <- BiblicalScrolls.check(conn) do
      readings =
        if groups,
          do: BiblicalScrolls.at(conn, group_references(groups)),
          else: BiblicalScrolls.range(conn, book, verse_bound(start), verse_bound(finish))

      {:ok, Enum.map(readings, &dss_row/1), BiblicalScrolls.source_url(conn)}
    end
  end

  defp group_references(groups),
    do: groups |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp verse_bound({chapter, verse, _suffix}), do: {chapter, verse}

  # The witness rows (DSS, SP) merged into the MT and LXX rows. Canonical
  # numbering sorts every row by verse; Greek numbering keeps the LXX
  # groups' order and puts each verse's witness rows after the group's rows
  # (also when the group shows no MT or LXX row).
  defp merge_witnesses(rows, [], _groups, _versions), do: rows

  defp merge_witnesses(rows, witness_rows, nil, versions) do
    order = version_order(versions)

    (rows ++ witness_rows)
    |> Enum.sort_by(
      &{&1.canonical_chapter, &1.canonical_verse, &1.canonical_verse_suffix, order.(&1),
       &1.edition, Map.get(&1, :position, 0)}
    )
    |> Enum.map(&Map.delete(&1, :position))
  end

  defp merge_witnesses(rows, witness_rows, groups, versions) do
    by_reference =
      witness_rows
      |> Enum.sort_by(version_order(versions))
      |> Enum.group_by(& &1.canonical_reference)

    by_group = Enum.group_by(rows, &group/1)

    {merged, _} =
      Enum.flat_map_reduce(groups, MapSet.new(), fn {key, reference}, seen ->
        shown = Map.get(by_group, key, [])

        if reference && not MapSet.member?(seen, reference),
          do: {shown ++ Map.get(by_reference, reference, []), MapSet.put(seen, reference)},
          else: {shown, seen}
      end)

    Enum.map(merged, &Map.delete(&1, :position))
  end

  defp dss_row(reading) do
    name = if reading.name, do: " (#{reading.name})", else: ""

    %{
      version: "DSS",
      edition: BiblicalScrolls.edition(),
      language: reading.language,
      canonical_reference: reading.reference,
      canonical_book: reading.book,
      canonical_chapter: reading.chapter,
      canonical_verse: reading.verse,
      canonical_verse_suffix: "",
      edition_reference: "#{reading.siglum}#{name} #{reading.locator}",
      text: reading.text,
      translation: nil,
      translation_label: "none",
      translation_note: nil,
      license: BiblicalScrolls.license(),
      source_url: nil,
      mapping_method: dss_mapping(reading),
      morphology: [],
      apocrypha: nil,
      kjv_apocrypha: false,
      brenton: brenton(:not_applicable),
      dss: %{
        siglum: reading.siglum,
        name: reading.name,
        site: reading.site,
        locator: reading.locator,
        letters: reading.letters,
        preserved_letters: reading.preserved_letters,
        source_reference: reading.source_reference,
        mt_verse: reading.mt_verse
      },
      position: {reading.sort_order, reading.occurrence}
    }
  end

  defp dss_mapping(%{mt_verse: false} = reading),
    do: "ETCBC numbering #{reading.source_reference}; no such MT verse"

  defp dss_mapping(%{reference: same, source_reference: same}), do: "identity"
  defp dss_mapping(reading), do: "Hebrew numbering #{reading.source_reference}"

  defp sp_row(verse, source) do
    [_, own_chapter, own_verse] =
      verse.source_reference |> String.split(".") |> Enum.map(&parse_int/1)

    %{
      version: "SP",
      edition: @sp_edition,
      language: "Hebrew",
      canonical_reference: verse.reference,
      canonical_book: verse.book,
      canonical_chapter: verse.chapter,
      canonical_verse: verse.verse,
      canonical_verse_suffix: "",
      edition_reference: verse.source_reference,
      text: verse.text,
      translation: nil,
      translation_label: "none",
      translation_note: nil,
      license: source.licence,
      source_url: source.source_url,
      mapping_method: sp_mapping(verse),
      morphology: [],
      apocrypha: nil,
      kjv_apocrypha: false,
      brenton: brenton(:not_applicable),
      sp: %{
        source_reference: verse.source_reference,
        note: verse.note,
        source_url: source.source_url,
        attribution: source.attribution
      },
      position: {own_chapter, own_verse}
    }
  end

  defp parse_int(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> text
    end
  end

  defp sp_mapping(%{mt_verse: false} = verse),
    do: "dataset numbering #{verse.source_reference}; no such MT verse"

  defp sp_mapping(%{reference: same, source_reference: same}), do: "identity"
  defp sp_mapping(verse), do: "Hebrew numbering #{verse.source_reference}"

  # --- The New Testament -------------------------------------------------------

  # The core pack's Greek (TAGNT) and the SBLGNT, grouped by the core pack's
  # verse numbering (the SBLGNT's own). The core pack is required; the
  # witnesses pack is a note when missing, the error when SBLGNT is asked
  # for alone.
  defp nt_result(reference, {book, start, finish}, requested, args, prefs) do
    with {:ok, versions} <- testament(requested, @nt_versions, reference),
         {:ok, sblgnt} <- sblgnt_status(versions),
         {:ok, tagnt} <-
           if("TAGNT" in versions,
             do: DB.with_pack(:core, &tagnt_rows(&1, book, start, finish)),
             else: {:ok, []}
           ),
         {:ok, sblgnt_rows, sblgnt} <- sblgnt_rows(sblgnt, {book, start, finish}, versions) do
      order = version_order(versions)

      rows =
        (tagnt ++ sblgnt_rows)
        |> Enum.sort_by(&{&1.canonical_chapter, &1.canonical_verse, order.(&1), &1.position})
        |> Enum.map(&Map.delete(&1, :position))

      {rows, cap_note} = cap(reference, rows, "canonical")

      {:ok,
       %{
         reference: reference,
         versions: versions,
         numbering: "canonical",
         include_original: Args.flag(args, "include_original", true),
         include_morphology: Args.flag(args, "include_morphology", false),
         rows: rows,
         lxx_only: [],
         cap_note: cap_note,
         dss: :off,
         dss_source_url: nil,
         sp: :off,
         sblgnt: sblgnt,
         prefs: prefs
       }}
    end
  end

  defp sblgnt_status(versions) do
    cond do
      "SBLGNT" not in versions -> {:ok, :off}
      DB.available?(:witnesses) -> {:ok, :on}
      versions == ["SBLGNT"] -> {:error, DB.missing(:witnesses)}
      true -> {:ok, :missing}
    end
  end

  defp sblgnt_rows(sblgnt, _passage, _versions) when sblgnt != :on, do: {:ok, [], sblgnt}

  defp sblgnt_rows(:on, {book, start, finish}, versions) do
    read = fn conn ->
      with :ok <- Witnesses.check(conn, ["sblgnt_verses"]),
           {:ok, source} <- Witnesses.source(conn, "sblgnt") do
        verses = Witnesses.sblgnt(conn, book, verse_bound(start), verse_bound(finish))
        {:ok, Enum.map(verses, &sblgnt_row(&1, source))}
      end
    end

    case DB.with_pack(:witnesses, read) do
      {:ok, {:ok, rows}} -> {:ok, rows, :on}
      {_, {:error, message}} when versions == ["SBLGNT"] -> {:error, message}
      {:error, message} when versions == ["SBLGNT"] -> {:error, message}
      _damaged -> {:ok, [], :missing}
    end
  end

  defp sblgnt_row(verse, source) do
    %{
      version: "SBLGNT",
      edition: @sblgnt_edition,
      language: "Greek",
      canonical_reference: verse.reference,
      canonical_book: verse.book,
      canonical_chapter: verse.chapter,
      canonical_verse: verse.verse,
      canonical_verse_suffix: "",
      edition_reference: verse.reference,
      text: verse.text,
      translation: nil,
      translation_label: "none",
      translation_note: nil,
      license: source.licence,
      source_url: source.source_url,
      mapping_method: "identity",
      morphology: [],
      apocrypha: nil,
      kjv_apocrypha: false,
      brenton: brenton(:not_applicable),
      sblgnt: %{
        file: verse.file,
        line: verse.line,
        source_url: source.source_url,
        attribution: source.attribution
      },
      position: 0
    }
  end

  # The core pack's NT verses, grouped under their chapter and verse (two
  # rows can share one: '2Co.13.12' and '2Co.13.12[13.13]').
  defp tagnt_rows(conn, book, start, finish) do
    conn
    |> DB.all(
      """
      SELECT id, reference, chapter, verse, text_original, text_english, word_data
      FROM verses
      WHERE book = ? AND text_original IS NOT NULL
        AND (chapter, verse, '') BETWEEN (?, ?, ?) AND (?, ?, ?)
      ORDER BY chapter, verse, id
      """,
      [book | Tuple.to_list(start) ++ Tuple.to_list(finish)]
    )
    |> Enum.map(fn verse ->
      canonical = "#{book}.#{verse["chapter"]}.#{verse["verse"]}"

      %{
        version: "TAGNT",
        edition: @tagnt_edition,
        language: "Greek",
        canonical_reference: canonical,
        canonical_book: book,
        canonical_chapter: verse["chapter"],
        canonical_verse: verse["verse"],
        canonical_verse_suffix: "",
        edition_reference: verse["reference"],
        text: verse["text_original"],
        translation: verse["text_english"],
        translation_label: @mt_translation_label,
        translation_note: nil,
        license: @mt_license,
        source_url: @mt_source_url,
        mapping_method:
          if(verse["reference"] == canonical, do: "identity", else: "STEP #{verse["reference"]}"),
        morphology: mt_words(verse["word_data"]),
        apocrypha: nil,
        kjv_apocrypha: false,
        brenton: brenton(:not_applicable),
        position: verse["id"]
      }
    end)
  end

  defp present(""), do: {:error, "Please provide a verse reference (e.g., 'Psalm 24:1')."}
  defp present(_reference), do: :ok

  # An LXX-only book has no MT to show.
  defp needs_lxx([], book, versions, reference) when book in @lxx_only_books do
    if "LXX" in versions,
      do: :ok,
      else:
        {:error,
         "#{reference} is in a Septuagint-only book with no Masoretic Text; " <>
           "include 'LXX' in versions."}
  end

  defp needs_lxx(_rows, _book, _versions, _reference), do: :ok

  defp versions(requested) when is_list(requested) and requested != [] do
    versions = requested |> Enum.map(&(&1 |> python_str() |> String.upcase())) |> Enum.uniq()

    case Enum.reject(versions, &(&1 in @versions)) do
      [] ->
        {:ok, versions}

      unsupported ->
        {:error,
         "Unsupported biblical version(s): #{Enum.join(unsupported, ", ")}. Use MT, LXX, DSS " <>
           "and/or SP (Old Testament), or TAGNT and/or SBLGNT (New Testament)."}
    end
  end

  defp versions(_),
    do:
      {:error,
       "'versions' must be a non-empty list containing MT, LXX, DSS and/or SP (Old " <>
         "Testament), or TAGNT and/or SBLGNT (New Testament)."}

  defp numbering(value) do
    case value |> python_str() |> String.downcase() do
      numbering when numbering in ["canonical", "lxx"] ->
        {:ok, numbering}

      numbering ->
        {:error,
         "Unsupported numbering '#{numbering}'. Use 'canonical' (MT/English) or 'lxx' (Greek edition)."}
    end
  end

  # Python's str() of a JSON value, as their handler applies it.
  defp python_str(value) when is_binary(value), do: value
  defp python_str(nil), do: "None"
  defp python_str(true), do: "True"
  defp python_str(false), do: "False"
  defp python_str(value) when is_number(value), do: to_string(value)
  defp python_str(value), do: inspect(value)

  defp book(reference) do
    case Ancient.parse_passage_reference(reference) do
      nil ->
        {:error,
         "Could not parse '#{reference}'. Use 'Book chapter:verse' (e.g. 'Psalm 82:6'), " <>
           "a range within or across chapters ('Psalm 82:1-8', 'Psalm 81:6-82:1'), " <>
           "or a whole chapter ('Psalm 82')."}

      {_name, code, start, finish}
      when code in @nt_books or code in @mt_books or code in @lxx_only_books ->
        {:ok, code, start, finish}

      {name, code, _start, _finish} ->
        {:error,
         "'#{code || name}' is not a book covered by compare_biblical_versions. Supported: " <>
           "the Old Testament books (MT and LXX; Genesis–Deuteronomy also SP), the New " <>
           "Testament books (TAGNT and SBLGNT), and the Septuagint-only books Tobit, Judith, " <>
           "Wisdom, Sirach, Baruch, Letter of Jeremiah, 1-4 Maccabees, 1-2 Esdras, Greek Esther, " <>
           "Susanna, Bel and the Dragon, Odes, and Psalms of Solomon."}
    end
  end

  defp fetch(book, start, finish, versions, "lxx") do
    with {:ok, lxx_rows} <-
           DB.with_pack(:lxx, fn conn ->
             conn
             |> DB.all(
               """
               SELECT #{@lxx_columns} FROM biblical_version_verses
               WHERE edition_book = ?
                 AND (edition_chapter, edition_verse, edition_verse_suffix)
                     BETWEEN (?, ?, ?) AND (?, ?, ?)
               ORDER BY edition_chapter, edition_verse, edition_verse_suffix,
                        edition, canonical_chapter, canonical_verse
               """,
               [book | Tuple.to_list(start) ++ Tuple.to_list(finish)]
             )
             |> Enum.map(&lxx_row/1)
           end),
         {:ok, mt_rows} <- mt_for_lxx(lxx_rows, versions) do
      keys = lxx_rows |> Enum.map(&group/1) |> Enum.uniq()
      lxx = if "LXX" in versions, do: lxx_rows, else: []
      order = version_order(versions)

      rows =
        Enum.flat_map(keys, fn key ->
          (Enum.filter(lxx, &(group(&1) == key)) ++ Enum.filter(mt_rows, &(group(&1) == key)))
          |> Enum.sort_by(&{order.(&1), &1.edition, &1.position})
        end)

      groups =
        Enum.map(keys, fn key ->
          {key, Enum.find(lxx_rows, &(group(&1) == key)).canonical_reference}
        end)

      {:ok, {Enum.map(rows, &Map.delete(&1, :position)), [], groups}}
    end
  end

  defp fetch(book, start, finish, versions, "canonical") do
    # The lxx pack first: theirs reports missing LXX data before reading the MT.
    with {:ok, {lxx, lxx_only}} <-
           if("LXX" in versions,
             do: DB.with_pack(:lxx, &canonical_lxx(&1, book, start, finish)),
             else: {:ok, {[], []}}
           ),
         {:ok, mt} <-
           if("MT" in versions,
             do: DB.with_pack(:core, &mt_rows(&1, book, start, finish)),
             else: {:ok, []}
           ) do
      order = version_order(versions)

      rows =
        (mt ++ lxx)
        |> Enum.sort_by(
          &{&1.canonical_chapter, &1.canonical_verse, &1.canonical_verse_suffix, order.(&1),
           &1.edition, &1.position}
        )
        |> Enum.map(&Map.delete(&1, :position))

      {:ok, {rows, lxx_only, nil}}
    end
  end

  defp canonical_lxx(conn, book, start, finish) do
    params = [book | Tuple.to_list(start) ++ Tuple.to_list(finish)]

    rows =
      conn
      |> DB.all(
        """
        SELECT #{@lxx_columns} FROM biblical_version_verses
        WHERE canonical_book = ?
          AND (canonical_chapter, canonical_verse, canonical_verse_suffix)
              BETWEEN (?, ?, ?) AND (?, ?, ?)
        """,
        params
      )
      |> Enum.map(&lxx_row/1)

    lxx_only =
      conn
      |> DB.all(
        """
        SELECT edition, edition_reference FROM biblical_version_verses
        WHERE canonical_book IS NULL AND edition_book = ?
          AND (edition_chapter, edition_verse, edition_verse_suffix)
              BETWEEN (?, ?, ?) AND (?, ?, ?)
        ORDER BY edition_chapter, edition_verse, edition_verse_suffix, edition
        """,
        params
      )
      |> Enum.map(&%{edition: &1["edition"], edition_reference: &1["edition_reference"]})

    {rows, lxx_only}
  end

  # The MT rows of the canonical verses the LXX rows map to (a whole MT
  # chapter is read, its wanted verses kept).
  defp mt_for_lxx(lxx_rows, versions) do
    wanted =
      if "MT" in versions,
        do:
          for(
            row <- lxx_rows,
            row.canonical_book in @mt_books and row.canonical_verse_suffix == "",
            do: {row.canonical_book, row.canonical_chapter, row.canonical_verse}
          ),
        else: []

    chapters = wanted |> Enum.map(fn {book, chapter, _} -> {book, chapter} end) |> Enum.uniq()

    if chapters == [],
      do: {:ok, []},
      else: DB.with_pack(:core, &mt_chapters(&1, chapters, MapSet.new(wanted)))
  end

  defp mt_chapters(conn, chapters, wanted) do
    Enum.flat_map(chapters, fn {book, chapter} ->
      conn
      |> mt_rows(book, {chapter, 0, ""}, {chapter, 9999, "~"})
      |> Enum.filter(&MapSet.member?(wanted, {book, chapter, &1.canonical_verse}))
    end)
  end

  defp version_order(versions) do
    index = versions |> Enum.with_index() |> Map.new()
    &Map.get(index, &1.version, length(versions))
  end

  defp group(row), do: row.canonical_reference || "LXX-only #{row.edition_reference}"

  # MT rows built from the core pack's TAHOT verses (English numbering).
  defp mt_rows(conn, book, start, finish) do
    conn
    |> DB.all(
      """
      SELECT reference, chapter, verse, text_original, text_english, word_data
      FROM verses
      WHERE book = ? AND text_original IS NOT NULL
        AND (chapter, verse, '') BETWEEN (?, ?, ?) AND (?, ?, ?)
      ORDER BY chapter, verse, id
      """,
      [book | Tuple.to_list(start) ++ Tuple.to_list(finish)]
    )
    |> Enum.map(fn verse ->
      hebrew = Regex.run(Patterns.get(:hebrew_numbering), verse["reference"])

      {chapter, number} =
        case hebrew do
          [_, c, v] -> {String.to_integer(c), String.to_integer(v)}
          nil -> {verse["chapter"], verse["verse"]}
        end

      %{
        version: "MT",
        edition: @mt_edition,
        language: "Hebrew",
        canonical_reference: "#{book}.#{verse["chapter"]}.#{verse["verse"]}",
        canonical_book: book,
        canonical_chapter: verse["chapter"],
        canonical_verse: verse["verse"],
        canonical_verse_suffix: "",
        edition_reference: "#{book}.#{chapter}.#{number}",
        text: verse["text_original"],
        translation: verse["text_english"],
        translation_label: @mt_translation_label,
        translation_note: nil,
        license: @mt_license,
        source_url: @mt_source_url,
        mapping_method: if(hebrew, do: @mt_versification, else: "identity"),
        morphology: mt_words(verse["word_data"]),
        apocrypha: nil,
        kjv_apocrypha: false,
        brenton: brenton(:not_applicable),
        position: {chapter, number, ""}
      }
    end)
  end

  defp mt_words(nil), do: []

  defp mt_words(json) do
    case JSON.decode(json) do
      {:ok, words} when is_list(words) -> for word when is_map(word) <- words, do: word(word)
      _ -> []
    end
  end

  defp word(map) do
    get = fn key -> if Format.present?(map[key]), do: map[key] end

    %{
      surface: get.("surface") || get.("word") || "",
      lemma: get.("lemma"),
      strongs: get.("strongs"),
      parsing: get.("parsing") || get.("morph"),
      pos: get.("pos"),
      gloss: get.("gloss")
    }
  end

  # A stored LXX row with its constant provenance, the KJV Apocrypha and
  # Brenton's Greek sorted out (their _lxx_row).
  defp lxx_row(row) do
    [edition_book | _] = String.split(row["edition_reference"], ".", parts: 2)
    chapter = row["edition_chapter"]
    verse = row["edition_verse"]
    translated = Format.present?(row["translation"])
    kjv = translated and kjv_apocrypha?(edition_book, chapter, verse)

    {label, note, brenton} =
      cond do
        kjv -> {@kjv_label, @kjv_note, brenton(:not_applicable)}
        translated -> {@lxx_translation_label, @brenton_note, brenton(row)}
        true -> {@lxx_translation_label, nil, brenton(row)}
      end

    %{
      version: "LXX",
      edition: row["edition"],
      language: "Greek",
      canonical_reference: row["canonical_reference"],
      canonical_book: row["canonical_book"],
      canonical_chapter: row["canonical_chapter"],
      canonical_verse: row["canonical_verse"],
      canonical_verse_suffix: row["canonical_verse_suffix"],
      edition_reference: row["edition_reference"],
      text: row["text"],
      translation: row["translation"],
      translation_label: label,
      translation_note: note,
      license: @lxx_license,
      source_url: @lxx_source_url,
      mapping_method: row["mapping_method"],
      morphology: lxx_words(row["morphology"]),
      apocrypha: apocrypha(edition_book, chapter, verse, row["canonical_reference"]),
      kjv_apocrypha: kjv,
      brenton: brenton,
      position: {chapter, verse, row["edition_verse_suffix"]}
    }
  end

  defp brenton(%{"brenton_greek_differs" => nil}), do: brenton(:unavailable)
  defp brenton(%{"brenton_greek_differs" => 0}), do: brenton(:same)

  defp brenton(%{} = row),
    do: %{
      status: :differs,
      greek: row["brenton_greek"],
      difference: row["brenton_greek_difference"]
    }

  defp brenton(status), do: %{status: status, greek: nil, difference: nil}

  # The morphology column: zlib-compressed JSON arrays in
  # @lxx_morphology_fields order.
  defp lxx_words(blob) when blob in [nil, ""], do: []

  defp lxx_words(blob) do
    blob
    |> :zlib.uncompress()
    |> JSON.decode!()
    |> Enum.map(&(@lxx_morphology_fields |> Enum.zip(&1) |> Map.new() |> word()))
  end

  defp kjv_apocrypha?(book, chapter, verse),
    do: book in @kjv_books or (book == "Dan" and chapter == 3 and verse in 24..90)

  defp apocrypha(book, _chapter, _verse, _canonical) when is_map_key(@apocrypha_books, book),
    do: @apocrypha_books[book]

  defp apocrypha("Ode", chapter, _verse, _canonical), do: @noncanonical_odes[chapter]
  defp apocrypha("EsG", _chapter, _verse, nil), do: @esther_additions

  defp apocrypha("Dan", 3, verse, _canonical) when verse in 24..90,
    do: "#{@azariah} (Dan 3:24–90)"

  defp apocrypha("Psa", 151, _verse, _canonical), do: "Psalm 151"
  defp apocrypha(_book, _chapter, _verse, _canonical), do: nil

  # The first @max_verses verse groups, and where to resume.
  defp cap(reference, rows, numbering) do
    groups = rows |> Enum.map(&group/1) |> Enum.uniq()

    if length(groups) <= @max_verses do
      {rows, ""}
    else
      kept = groups |> Enum.take(@max_verses) |> MapSet.new()
      resume_group = Enum.at(groups, @max_verses)
      resume_rows = Enum.filter(rows, &(group(&1) == resume_group))
      resume = Enum.find(resume_rows, hd(resume_rows), &(&1.version == "LXX"))

      resume_at =
        case {numbering, resume.canonical_chapter,
              Regex.run(Patterns.get(:reference_book), reference)} do
          {"canonical", chapter, [_, book]} when chapter not in [nil, 0] ->
            "'#{String.trim(book)} #{resume.canonical_chapter}:#{resume.canonical_verse}'"

          _ ->
            "#{resume.edition_reference} (numbering='lxx')"
        end

      {Enum.filter(rows, &MapSet.member?(kept, group(&1))),
       "Showing the first #{@max_verses} of #{length(groups)} verses. " <>
         "Continue from #{resume_at} in another call."}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{rows: []} = result) do
    scheme =
      cond do
        result.numbering == "lxx" -> "Greek edition"
        Enum.all?(result.versions, &(&1 in @nt_versions)) -> "the core Greek text's"
        true -> "canonical MT/English"
      end

    message =
      "No #{Enum.join(result.versions, " or ")} text found for #{result.reference} (#{scheme} numbering)."

    case [lxx_only_note(result.lxx_only), dss_note(result), sp_note(result), sblgnt_note(result)]
         |> Enum.reject(&(&1 == "")) do
      [] -> message
      notes -> Enum.join([message | notes], "\n\n")
    end
  end

  def render(result) do
    note =
      [result.cap_note, lxx_only_note(result.lxx_only)]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    title =
      "## Biblical Version Comparison: #{result.reference}" <>
        if(result.numbering == "lxx", do: " (Septuagint edition numbering)", else: "")

    header =
      [title, ""] ++
        Enum.flat_map(
          [note, dss_note(result), sp_note(result), sblgnt_note(result)],
          &if(&1 != "", do: ["*#{&1}*", ""], else: [])
        )

    {lines, _group} =
      Enum.flat_map_reduce(result.rows, nil, fn row, current ->
        group =
          row.canonical_reference || "#{row.edition_reference} (LXX-only, no MT counterpart)"

        heading = if group != current, do: ["### #{group}", ""], else: []
        {heading ++ row_lines(row, result), group}
      end)

    (header ++ lines ++ sources(result.rows, result.prefs, result.dss_source_url))
    |> Enum.join("\n")
    |> String.trim_trailing()
  end

  defp row_lines(%{version: "DSS"} = row, result) do
    [row_header(row)] ++
      if(result.include_original, do: ["**#{row.language}:** #{row.text}"], else: []) ++
      [
        preservation(row.dss),
        "**English:** none (any English is the assistant's own).",
        Citation.source_line(row_citations(row)),
        ""
      ]
  end

  defp row_lines(%{version: version} = row, result) when version in ["SP", "SBLGNT"] do
    [row_header(row)] ++
      if(result.include_original, do: ["**#{row.language}:** #{row.text}"], else: []) ++
      sp_division(row) ++
      [
        "**English:** none (any English is the assistant's own).",
        Citation.source_line(row_citations(row)),
        ""
      ]
  end

  defp row_lines(row, result) do
    [row_header(row)] ++
      if(result.include_original, do: ["**#{row.language}:** #{row.text}"], else: []) ++
      brenton_lines(row.brenton, result.include_original) ++
      english_lines(row) ++
      [Citation.source_line(row_citations(row))] ++
      morphology_lines(row.morphology, result.include_morphology) ++ [""]
  end

  defp sp_division(%{sp: %{note: note}}) when is_binary(note), do: ["*Verse division: #{note}*"]
  defp sp_division(_row), do: []

  defp preservation(%{preserved_letters: 0}) do
    "*Nothing legible survives here outside the editors' reconstruction: every letter is in [ ], " <>
      "which is not evidence of what the scroll read.*"
  end

  defp preservation(%{letters: letters, preserved_letters: letters}),
    do: "*Every letter preserved (#{letters}).*"

  defp preservation(dss) do
    "*Preserved: #{dss.preserved_letters} of #{dss.letters} letters; the rest, in [ ], is " <>
      "the editors' reconstruction, not evidence.*"
  end

  # Whether the DSS witnesses are missing or absent.
  defp dss_note(%{dss: :missing}),
    do:
      "Dead Sea Scrolls readings need the scrolls study pack, which isn't downloaded on this " <>
        "device; tell the user if they matter."

  defp dss_note(%{dss: :on, rows: [_ | _] = rows}) do
    if Enum.any?(rows, &(&1.version == "DSS")),
      do: "",
      else: "No biblical Dead Sea Scroll (ETCBC/dss) preserves any of these verses."
  end

  defp dss_note(_result), do: ""

  # Whether the Samaritan Pentateuch is missing, or lacks a verse the MT has
  # (it groups some passages under other verses).
  defp sp_note(%{sp: :missing}),
    do:
      "Samaritan Pentateuch readings need the witnesses study pack, which isn't downloaded on " <>
        "this device; tell the user if they matter."

  defp sp_note(%{sp: :on, rows: rows}) do
    have = for %{version: "SP"} = row <- rows, into: MapSet.new(), do: row.canonical_reference

    case for(
           %{version: "MT"} = row <- rows,
           not MapSet.member?(have, row.canonical_reference),
           uniq: true,
           do: row.canonical_reference
         ) do
      [] ->
        ""

      lacking ->
        "The Samaritan Pentateuch dataset has no verse numbered #{Enum.join(lacking, ", ")}: " <>
          "it has no such text there or places it under another verse (its Exodus 26:35 " <>
          "holds the MT's 30:1–10)."
    end
  end

  defp sp_note(_result), do: ""

  # Whether the SBLGNT is missing, or doesn't print a verse the core text has.
  defp sblgnt_note(%{sblgnt: :missing}),
    do:
      "The SBL Greek New Testament needs the witnesses study pack, which isn't downloaded on " <>
        "this device; tell the user if it matters."

  defp sblgnt_note(%{sblgnt: :on, rows: rows}) do
    have = for %{version: "SBLGNT"} = row <- rows, into: MapSet.new(), do: row.canonical_reference

    case for(
           %{version: "TAGNT"} = row <- rows,
           not MapSet.member?(have, row.canonical_reference),
           uniq: true,
           do: row.canonical_reference
         ) do
      [] ->
        ""

      lacking ->
        "The SBLGNT doesn't print #{Enum.join(lacking, ", ")}: TAGNT includes the words some " <>
          "editions have there (get_textual_variant gives the SBLGNT apparatus)."
    end
  end

  defp sblgnt_note(_result), do: ""

  defp row_header(row) do
    mapping =
      if Format.present?(row.mapping_method) and row.mapping_method != "identity",
        do: " (mapping: #{row.mapping_method})",
        else: ""

    "#### #{row.version} #{row.edition} · #{row.edition_reference}#{mapping}" <>
      if(row.apocrypha, do: " (not in the Hebrew Bible)", else: "")
  end

  defp brenton_lines(%{status: :differs, greek: greek, difference: difference}, include_original) do
    [
      "> **Warning: Brenton's English below translates a different Greek text.** " <>
        "His own Greek differs from the Rahlfs text here: #{difference}"
    ] ++
      if(include_original,
        do: ["**Brenton's Greek (the text his English translates):** #{greek}"],
        else: []
      )
  end

  defp brenton_lines(_brenton, _include_original), do: []

  defp english_lines(row) do
    english =
      if Format.present?(row.translation),
        do: "**English (#{english_label(row)}):** #{row.translation}",
        else: "**English:** not available for this edition."

    if not row.kjv_apocrypha and row.translation_note != nil and
         row.brenton.status == :unavailable,
       do: [english, "*Brenton's Greek for this verse is unavailable, so it was not compared.*"],
       else: [english]
  end

  defp english_label(%{kjv_apocrypha: true}), do: "KJV Apocrypha"
  defp english_label(%{version: version}) when version in ["MT", "TAGNT"], do: "word glosses"
  defp english_label(_row), do: "Brenton"

  defp morphology_lines([_ | _] = words, true),
    do: ["**Morphology:**" | Enum.map(words, &word_line/1)]

  defp morphology_lines(_words, _include), do: []

  defp word_line(word) do
    details =
      [word.lemma || word.strongs, word.pos, word.parsing]
      |> Enum.reject(&(&1 == nil))
      |> Enum.join("; ")

    "- **#{word.surface}**" <>
      if(details != "", do: " (#{details})", else: "") <>
      if(word.gloss, do: " — #{word.gloss}", else: "")
  end

  # Provenance once: each edition's licence, English and source, the
  # verse-mapping credit, the canon and verdict lines (by `prefs`), and the
  # Brenton and KJV notes.
  defp sources(rows, prefs, dss_url) do
    editions = rows |> Enum.map(&{&1.version, &1.edition}) |> Enum.uniq()
    outside = rows |> Enum.map(& &1.apocrypha) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    ["---", "**Sources**"] ++
      Enum.map(editions, &edition_line(&1, rows, dss_url)) ++
      when_any(rows, &(&1.brenton.status == :differs), [
        "- Brenton's Greek: public domain. #{@brenton_greek_source_url}"
      ]) ++
      if(Enum.all?(rows, &(&1.version in @nt_versions)),
        do: [],
        else: ["- Verse mapping: #{@verse_mapping_credit}"]
      ) ++
      if(prefs.scripture_labels, do: canon_line(outside), else: []) ++
      if(Sources.enabled?(prefs, "editorial:verdicts"), do: verdict_line(outside), else: []) ++
      when_any(rows, &(not &1.kjv_apocrypha and &1.translation_note != nil), [
        "\n*Brenton's English: #{@brenton_note}*"
      ]) ++
      when_any(rows, & &1.kjv_apocrypha, ["\n*KJV Apocrypha English: #{@kjv_note}*"])
  end

  defp when_any(rows, fun, lines), do: if(Enum.any?(rows, fun), do: lines, else: [])

  defp edition_line({"DSS", edition}, _rows, url) do
    "- DSS #{edition}: Hebrew and Aramaic, #{BiblicalScrolls.transcription()}: " <>
      "#{BiblicalScrolls.license()}. English: none. Manuscript names: Leon Levy Dead Sea " <>
      "Scrolls Digital Library (IAA). [ ] marks modern reconstruction, never evidence. " <>
      (url || "https://github.com/ETCBC/dss")
  end

  defp edition_line({"SP", edition}, rows, _url) do
    %{sp: sp, license: license} = Enum.find(rows, &(&1.version == "SP"))

    "- SP #{edition}: consonantal Hebrew only (the letters the manuscripts spell, no vowel " <>
      "points or accents; the MT's pointing is the Masoretes'), #{sp.attribution}: " <>
      "#{license}. English: none. #{sp.source_url}"
  end

  defp edition_line({"TAGNT", edition}, rows, _url) do
    first = Enum.find(rows, &(&1.version == "TAGNT"))

    "- TAGNT #{edition} (Greek), #{@tagnt_note}: #{first.license}. " <>
      "English: #{first.translation_label}. #{first.source_url}"
  end

  defp edition_line({"SBLGNT", edition}, rows, _url) do
    %{sblgnt: s, license: license} = Enum.find(rows, &(&1.version == "SBLGNT"))

    "- SBLGNT #{edition} (Greek, ed. Michael W. Holmes), #{s.attribution}: #{license}. " <>
      "English: none. ⸀ ⸁ ⸂ ⸃ ⸄ ⸅ mark where its apparatus has a note (get_textual_variant). " <>
      s.source_url
  end

  defp edition_line({version, edition}, rows, _url) do
    [first | _] =
      of_edition = Enum.filter(rows, &({&1.version, &1.edition} == {version, edition}))

    english =
      case of_edition
           |> Enum.filter(&Format.present?(&1.translation))
           |> Enum.map(& &1.translation_label)
           |> Enum.uniq() do
        [] -> "none"
        labels -> Enum.join(labels, "; ")
      end

    "- #{version} #{edition} (#{first.language}): #{first.license}. " <>
      "English: #{english}. #{first.source_url}"
  end

  defp canon_line([]), do: []

  # 'Canon: Sirach is in the Catholic and Orthodox canons, not the Jewish or
  # Protestant ones.', one sentence per group of canons.
  defp canon_line(names) do
    sentences =
      names
      |> Enum.group_by(&canons/1)
      |> Enum.sort_by(fn {canons, _} -> canon_order(canons) end)
      |> Enum.map_join(" ", fn {canons, group} -> "#{listed(group)} #{canons}." end)

    ["\n*Canon: #{sentences}*"]
  end

  defp canons(name) do
    Enum.find_value(@canons, @outside_canons, fn {names, canons} ->
      if name in names, do: canons
    end)
  end

  defp canon_order(canons),
    do: Enum.find_index(@canons, &(elem(&1, 1) == canons)) || length(@canons)

  defp verdict_line([]), do: []

  defp verdict_line(names) do
    [
      "\n*Verdict (studybible-mcp): #{listed(names)} not in the Protestant canon " <>
        "(cf. Westminster Confession 1.3); background only.*"
    ]
  end

  # 'Sirach is', 'Sirach and Tobit are'.
  defp listed(names) do
    {init, [last]} = Enum.split(names, -1)
    listed = if init == [], do: last, else: "#{Enum.join(init, ", ")} and #{last}"
    verb = if init != [] or last in @apocrypha_plural, do: "are", else: "is"
    "#{listed} #{verb}"
  end

  defp lxx_only_note([]), do: ""

  defp lxx_only_note(lxx_only) do
    listed = Enum.map_join(lxx_only, ", ", &"#{&1.edition_reference} (#{&1.edition})")

    "LXX-only verses with no MT counterpart occupy this position in Greek edition " <>
      "numbering: #{listed}. Request numbering='lxx' to view them."
  end
end
