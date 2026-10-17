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

  `result/1` returns the rows (MT and LXX, in display order) as data.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Ancient, Args, DB, Format, Patterns}

  @max_verses 10

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
    Compare the Masoretic Text (MT) and Septuagint (LXX) side by side for an Old Testament or Septuagint verse, range, or chapter. Not for the New Testament. Returns at most ten verses per call and names the verse to continue from.

    Rows are grouped by canonical MT/English reference and keep each edition's own reference, so Hebrew/Greek versification differences stay explicit (Psalm 82:6 = Greek Psa.81.6). MT: Westminster Leningrad Codex with STEPBible word glosses (not a translation). LXX: Rahlfs, with Brenton's English only where Brenton translated the same recension. Brenton translated his own Greek, not Rahlfs: where it differs the row warns and shows his Greek, and his English should be quoted as a rendering of that text; most Apocrypha rows carry the KJV Apocrypha instead. LXX-only verses (e.g. the Prayer of Azariah) need numbering='lxx'. Sources, licences, and the TVTMS verse-mapping credit are listed once at the end.\
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
          "items" => %{"type" => "string", "enum" => ["MT", "LXX"]},
          "default" => ["MT", "LXX"],
          "description" => "Editions to return, in display order. Default: MT and LXX"
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
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
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
  canonical lookup); `cap_note` says where a cut comparison continues. No
  rows: nothing matched.
  """
  @type t :: %{
          reference: String.t(),
          versions: [String.t()],
          numbering: String.t(),
          include_original: boolean(),
          include_morphology: boolean(),
          rows: [row()],
          lxx_only: [%{edition: String.t(), edition_reference: String.t()}],
          cap_note: String.t()
        }

  @doc """
  The rows comparing `args`' passage (none when nothing matched), or
  `{:error, message}` for arguments the tool can't use, a New Testament or
  uncovered book, an MT-only request for an LXX-only book, or a missing pack.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    reference = Args.reference(args)

    with :ok <- present(reference),
         {:ok, versions} <- versions(Map.get(args, "versions", ["MT", "LXX"])),
         {:ok, numbering} <- numbering(Map.get(args, "numbering", "canonical")),
         {:ok, book, start, finish} <- book(reference),
         numbering = if(book in @lxx_only_books, do: "lxx", else: numbering),
         {:ok, {rows, lxx_only}} <- fetch(book, start, finish, versions, numbering),
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
         cap_note: cap_note
       }}
    end
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

    case Enum.reject(versions, &(&1 in ["MT", "LXX"])) do
      [] ->
        {:ok, versions}

      unsupported ->
        {:error,
         "Unsupported biblical version(s): #{Enum.join(unsupported, ", ")}. Use MT and/or LXX."}
    end
  end

  defp versions(_), do: {:error, "'versions' must be a non-empty list containing MT and/or LXX."}

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

      {_name, code, _start, _finish} when code in @nt_books ->
        {:error,
         "#{reference} is a New Testament reference. compare_biblical_versions covers " <>
           "Old Testament and Septuagint books only; use lookup_verse for New Testament text."}

      {_name, code, start, finish} when code in @mt_books or code in @lxx_only_books ->
        {:ok, code, start, finish}

      {name, code, _start, _finish} ->
        {:error,
         "'#{code || name}' is not a book covered by compare_biblical_versions. Supported: " <>
           "the Old Testament books (MT and LXX) and the Septuagint-only books Tobit, Judith, " <>
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

      {:ok, {Enum.map(rows, &Map.delete(&1, :position)), []}}
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

      {:ok, {rows, lxx_only}}
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
    scheme = if result.numbering == "lxx", do: "Greek edition", else: "canonical MT/English"

    message =
      "No #{Enum.join(result.versions, " or ")} text found for #{result.reference} (#{scheme} numbering)."

    case lxx_only_note(result.lxx_only) do
      "" -> message
      note -> "#{message}\n\n#{note}"
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

    header = [title, ""] ++ if(note != "", do: ["*#{note}*", ""], else: [])

    {lines, _group} =
      Enum.flat_map_reduce(result.rows, nil, fn row, current ->
        group =
          row.canonical_reference || "#{row.edition_reference} (LXX-only, no MT counterpart)"

        heading = if group != current, do: ["### #{group}", ""], else: []
        {heading ++ row_lines(row, result), group}
      end)

    (header ++ lines ++ sources(result.rows))
    |> Enum.join("\n")
    |> String.trim_trailing()
  end

  defp row_lines(row, result) do
    [row_header(row)] ++
      if(result.include_original, do: ["**#{row.language}:** #{row.text}"], else: []) ++
      brenton_lines(row.brenton, result.include_original) ++
      english_lines(row) ++
      morphology_lines(row.morphology, result.include_morphology) ++ [""]
  end

  defp row_header(row) do
    mapping =
      if Format.present?(row.mapping_method) and row.mapping_method != "identity",
        do: " (mapping: #{row.mapping_method})",
        else: ""

    "#### #{row.version} #{row.edition} · #{row.edition_reference}#{mapping}" <>
      if(row.apocrypha, do: " (Apocrypha)", else: "")
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
  defp english_label(%{version: "MT"}), do: "word glosses"
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
  # verse-mapping credit, and the Apocrypha, Brenton and KJV notes.
  defp sources(rows) do
    editions = rows |> Enum.map(&{&1.version, &1.edition}) |> Enum.uniq()

    ["---", "**Sources**"] ++
      Enum.map(editions, &edition_line(&1, rows)) ++
      when_any(rows, &(&1.brenton.status == :differs), [
        "- Brenton's Greek: public domain. #{@brenton_greek_source_url}"
      ]) ++
      ["- Verse mapping: #{@verse_mapping_credit}"] ++
      apocrypha_line(rows |> Enum.map(& &1.apocrypha) |> Enum.reject(&is_nil/1) |> Enum.uniq()) ++
      when_any(rows, &(not &1.kjv_apocrypha and &1.translation_note != nil), [
        "\n*Brenton's English: #{@brenton_note}*"
      ]) ++
      when_any(rows, & &1.kjv_apocrypha, ["\n*KJV Apocrypha English: #{@kjv_note}*"])
  end

  defp when_any(rows, fun, lines), do: if(Enum.any?(rows, fun), do: lines, else: [])

  defp edition_line({version, edition}, rows) do
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

  defp apocrypha_line([]), do: []

  defp apocrypha_line(names) do
    {init, [last]} = Enum.split(names, -1)
    listed = if init == [], do: last, else: "#{Enum.join(init, ", ")} and #{last}"
    verb = if init != [] or last in @apocrypha_plural, do: "are", else: "is"

    [
      "\n*Apocrypha: #{listed} #{verb} not in the Protestant canon " <>
        "(cf. Westminster Confession 1.3); background only.*"
    ]
  end

  defp lxx_only_note([]), do: ""

  defp lxx_only_note(lxx_only) do
    listed = Enum.map_join(lxx_only, ", ", &"#{&1.edition_reference} (#{&1.edition})")

    "LXX-only verses with no MT counterpart occupy this position in Greek edition " <>
      "numbering: #{listed}. Request numbering='lxx' to view them."
  end
end
