defmodule Bezalel.Study.Witnesses do
  @moduledoc """
  The witnesses pack (built by `data/`'s `mix bezalel.data.witnesses`),
  each source in tables of its own with its licence:

    * the Samaritan Pentateuch (`sp_verses`, DT-UCPH/sp, CC BY-NC 4.0):
      a verse's consonantal text, under the packs' English reference
      (`reference`) with the dataset's own number (`source_reference`);
    * the SBL Greek New Testament (`sblgnt_verses`, CC BY 4.0), in its own
      numbering, which is the core pack's `verses` numbering;
    * the SBLGNT apparatus (`sblgnt_apparatus`, CC BY 4.0): each variation
      unit with the SBLGNT's reading and the editions supporting it, then
      the variants with theirs, or the raw note when it couldn't be parsed;
    * the UBS Hebrew Old Testament Text Project (`hottp_*`, CC BY-SA 4.0):
      its entries at a verse, each alternative reading with the committee's
      rating and factors, and the glossaries of both.

  `compare_biblical_versions` shows the first two beside the MT, LXX and
  the core pack's Greek; `get_textual_variant` the last two; `lookup_verse`
  hints that the last two have something for a passage.
  """

  alias Bezalel.Study.DB

  @type source :: %{
          key: String.t(),
          name: String.t(),
          licence: String.t(),
          licence_url: String.t(),
          attribution: String.t(),
          source_url: String.t()
        }

  @type sp_verse :: %{
          reference: String.t(),
          book: String.t(),
          chapter: integer(),
          verse: integer(),
          source_reference: String.t(),
          mt_verse: boolean(),
          text: String.t(),
          note: String.t() | nil
        }

  @type sblgnt_verse :: %{
          reference: String.t(),
          book: String.t(),
          chapter: integer(),
          verse: integer(),
          text: String.t(),
          file: String.t(),
          line: pos_integer()
        }

  @typedoc """
  A variation unit: `lemma` the SBLGNT's reading, `lemma_sigla` the
  editions with it, `variants` each other reading (`text` may start with
  '+', added, or be '–', omitted; '' is the SBLGNT's own words in WH's
  double brackets) with its editions; `verses` the span a unit covers
  ('43–44'), else nil. An unparsed unit has only its `note`.
  """
  @type unit :: %{
          reference: String.t(),
          unit: pos_integer(),
          verses: String.t() | nil,
          note: String.t(),
          parsed: boolean(),
          lemma: String.t() | nil,
          lemma_sigla: [String.t()],
          variants: [%{text: String.t(), sigla: [String.t()]}],
          file: String.t(),
          line: pos_integer()
        }

  @type alternative :: %{
          position: pos_integer(),
          hebrew: String.t() | nil,
          rating: String.t() | nil,
          grade: String.t() | nil,
          factors: [String.t()],
          literal: String.t() | nil,
          renderings: [%{version: String.t(), text: String.t() | nil}]
        }

  @type entry :: %{
          id: String.t(),
          reference: String.t(),
          source_reference: String.t(),
          mt_verse: boolean(),
          remark: String.t() | nil,
          suggestion: String.t() | nil,
          alternatives: [alternative()]
        }

  @doc "`:ok` if `tables` of the pack can be read, else the damaged-pack error."
  @spec check(DB.conn(), [String.t()]) :: :ok | {:error, String.t()}
  def check(conn, tables), do: DB.check_tables(conn, :witnesses, ["witness_sources" | tables])

  # The apparatus's sigla, as the SBLGNT's introduction (Michael W. Holmes,
  # "Abbreviations Used in the Notes", sblgnt.com) and Logos's 2013 update
  # (NA28 cited throughout, NIV and NA27 only where they differ from it)
  # define them.
  @sigla %{
    "WH" => "Westcott and Hort, The New Testament in the Original Greek (1881)",
    "⟦WH⟧" =>
      "Westcott and Hort, who put the words in double brackets (material they doubted but kept)",
    "WHmarg" => "an alternative reading Westcott and Hort printed in their margin",
    "WHapp" => "a reading Westcott and Hort discuss in their Appendix",
    "Treg" => "Tregelles, The Greek New Testament (1857–1879)",
    "Tregmarg" => "a reading Tregelles printed in his margin",
    "NA28" => "Nestle–Aland, 28th edition (2012)",
    "NA27" => "Nestle–Aland, 27th edition (cited where it differs from NA28)",
    "NIV" =>
      "the Greek text behind the NIV (Goodrich and Lukaszewski, A Reader's Greek New " <>
        "Testament, 2003; cited where it differs from NA28)",
    "RP" =>
      "Robinson and Pierpont, The New Testament in the Original Greek: Byzantine Textform 2005",
    "TR" => "the Textus Receptus (Stephanus 1550, as printed by Nestle, 1906)",
    "Greeven" => "the text Heinrich Greeven printed in Huck's Synopsis (13th ed., 1981)",
    "Holmes" =>
      "the SBLGNT editor's preferred reading, found in none of the four primary editions",
    "em" => "emendation (a conjecture; the edition named next adopts or proposes it)"
  }

  @doc "What an apparatus siglum stands for, or nil."
  @spec siglum(String.t()) :: String.t() | nil
  def siglum(siglum), do: Map.get(@sigla, siglum)

  @doc "The pack's sources (`witness_sources`), by key: sp, sblgnt, sblgnt_apparatus, hottp."
  @spec sources(DB.conn()) :: %{String.t() => source()}
  def sources(conn) do
    conn
    |> DB.all(
      "SELECT key, name, licence, licence_url, attribution, source_url FROM witness_sources"
    )
    |> Map.new(fn row ->
      {row["key"], atomize(row, ~w(key name licence licence_url attribution source_url)a)}
    end)
  end

  @doc "The source `key` of the pack, or the damaged-pack error when it has no such row."
  @spec source(DB.conn(), String.t()) :: {:ok, source()} | {:error, String.t()}
  def source(conn, key) do
    case sources(conn)[key] do
      nil ->
        {:error,
         "The witnesses study pack on this device can't be read (no #{key} source); " <>
           "it may need downloading again."}

      source ->
        {:ok, source}
    end
  end

  @doc """
  The Samaritan Pentateuch's verses of `book` from `{chapter, verse}` to
  `{chapter, verse}` (English numbering, inclusive), in order.
  """
  @spec samaritan(DB.conn(), String.t(), {integer(), integer()}, {integer(), integer()}) ::
          [sp_verse()]
  def samaritan(conn, book, {chapter, verse}, {end_chapter, end_verse}) do
    conn
    |> DB.all(
      """
      SELECT reference, book, chapter, verse, source_reference, mt_verse, text, note
      FROM sp_verses
      WHERE book = ? AND (chapter, verse) BETWEEN (?, ?) AND (?, ?)
      ORDER BY chapter, verse, rowid
      """,
      [book, chapter, verse, end_chapter, end_verse]
    )
    |> Enum.map(&sp_verse/1)
  end

  @doc "The Samaritan Pentateuch's verses filed under `references` (English numbering)."
  @spec samaritan_at(DB.conn(), [String.t()]) :: [sp_verse()]
  def samaritan_at(_conn, []), do: []

  def samaritan_at(conn, references) do
    conn
    |> DB.all(
      """
      SELECT reference, book, chapter, verse, source_reference, mt_verse, text, note
      FROM sp_verses WHERE reference IN (#{DB.placeholders(references)}) ORDER BY rowid
      """,
      references
    )
    |> Enum.map(&sp_verse/1)
  end

  defp sp_verse(row) do
    %{
      reference: row["reference"],
      book: row["book"],
      chapter: row["chapter"],
      verse: row["verse"],
      source_reference: row["source_reference"],
      mt_verse: row["mt_verse"] == 1,
      text: row["text"],
      note: row["note"]
    }
  end

  @doc "The SBLGNT's verses of `book` from `{chapter, verse}` to `{chapter, verse}`, in order."
  @spec sblgnt(DB.conn(), String.t(), {integer(), integer()}, {integer(), integer()}) ::
          [sblgnt_verse()]
  def sblgnt(conn, book, {chapter, verse}, {end_chapter, end_verse}) do
    conn
    |> DB.all(
      """
      SELECT reference, book, chapter, verse, text, file, line FROM sblgnt_verses
      WHERE book = ? AND (chapter, verse) BETWEEN (?, ?) AND (?, ?)
      ORDER BY chapter, verse
      """,
      [book, chapter, verse, end_chapter, end_verse]
    )
    |> Enum.map(&atomize(&1, ~w(reference book chapter verse text file line)a))
  end

  @doc "The apparatus's variation units at `reference` ('Jhn.1.18'), in order."
  @spec apparatus(DB.conn(), String.t()) :: [unit()]
  def apparatus(conn, reference) do
    conn
    |> DB.all(
      """
      SELECT reference, unit, verses, note, parsed, lemma, lemma_sigla, variants, file, line
      FROM sblgnt_apparatus WHERE reference = ? ORDER BY unit
      """,
      [reference]
    )
    |> Enum.map(fn row ->
      %{
        reference: row["reference"],
        unit: row["unit"],
        verses: row["verses"],
        note: row["note"],
        parsed: row["parsed"] == 1,
        lemma: row["lemma"],
        lemma_sigla: json(row["lemma_sigla"]),
        variants: for(v <- json(row["variants"]), do: %{text: v["text"], sigla: v["sigla"]}),
        file: row["file"],
        line: row["line"]
      }
    end)
  end

  @doc "The HOTTP entries at `reference` (English numbering), each with its alternatives."
  @spec hottp(DB.conn(), String.t()) :: [entry()]
  def hottp(conn, reference) do
    entries =
      DB.all(
        conn,
        """
        SELECT v.entry_id, v.reference, v.source_reference, v.mt_verse, e.remark, e.suggestion
        FROM hottp_verses v JOIN hottp_entries e ON e.id = v.entry_id
        WHERE v.reference = ? ORDER BY v.entry_id, v.source_reference
        """,
        [reference]
      )

    ids = entries |> Enum.map(& &1["entry_id"]) |> Enum.uniq()

    alternatives =
      if ids == [],
        do: %{},
        else:
          conn
          |> DB.all(
            """
            SELECT entry_id, position, hebrew, rating, grade, factors, literal, renderings
            FROM hottp_alternatives WHERE entry_id IN (#{DB.placeholders(ids)})
            ORDER BY entry_id, position
            """,
            ids
          )
          |> Enum.group_by(& &1["entry_id"], &alternative/1)

    for row <- entries do
      %{
        id: row["entry_id"],
        reference: row["reference"],
        source_reference: row["source_reference"],
        mt_verse: row["mt_verse"] == 1,
        remark: row["remark"],
        suggestion: row["suggestion"],
        alternatives: Map.get(alternatives, row["entry_id"], [])
      }
    end
  end

  defp alternative(row) do
    %{
      position: row["position"],
      hebrew: row["hebrew"],
      rating: row["rating"],
      grade: row["grade"],
      factors: json(row["factors"]),
      literal: row["literal"],
      renderings: for(r <- json(row["renderings"]), do: %{version: r["version"], text: r["text"]})
    }
  end

  @doc "The rating glossary: grade ('A'–'D') → meaning."
  @spec ratings(DB.conn()) :: %{String.t() => String.t()}
  def ratings(conn) do
    conn
    |> DB.all("SELECT grade, meaning FROM hottp_ratings")
    |> Map.new(&{&1["grade"], &1["meaning"]})
  end

  @doc "The factor glossary: number → `%{kind, name, explanation}`."
  @spec factors(DB.conn()) :: %{integer() => map()}
  def factors(conn) do
    conn
    |> DB.all("SELECT number, kind, name, explanation FROM hottp_factors")
    |> Map.new(
      &{&1["number"], %{kind: &1["kind"], name: &1["name"], explanation: &1["explanation"]}}
    )
  end

  @doc """
  The references of `book` from chapter·1000+verse `low` to `high` that
  have HOTTP entries or apparatus units: `%{hottp: refs, apparatus: refs}`.
  """
  @spec hints(DB.conn(), String.t(), integer(), integer()) :: %{
          hottp: [String.t()],
          apparatus: [String.t()]
        }
  def hints(conn, book, low, high) do
    read = fn table ->
      conn
      |> DB.all(
        """
        SELECT DISTINCT reference FROM #{table}
        WHERE book = ? AND chapter * 1000 + verse BETWEEN ? AND ?
        ORDER BY chapter, verse
        """,
        [book, low, high]
      )
      |> Enum.map(& &1["reference"])
    end

    %{hottp: read.("hottp_verses"), apparatus: read.("sblgnt_apparatus")}
  end

  defp atomize(row, keys), do: Map.new(keys, &{&1, row[Atom.to_string(&1)]})

  defp json(nil), do: []
  defp json(text), do: JSON.decode!(text)
end
