defmodule Bezalel.Data.ScrollsPack do
  @moduledoc """
  Writes the `scrolls` pack (`Bezalel.Data.Pack.build/5`):

    * the non-biblical works' passages in the ancient pack's own tables and
      schema (`ancient_source_passages`, its FTS5 index
      `ancient_source_passages_fts` with the same columns and tokenizer, and
      the empty `ancient_source_biblical_links` and `ancient_source_notes`),
      so the ancient-source tools read either pack with the same SQL;
    * the biblical manuscripts (`dss_biblical_manuscripts`) and their verse
      readings (`dss_biblical_verses`).
  """

  alias Bezalel.Data.{Pack, Scrolls}

  @pack %{
    name: "scrolls",
    description:
      "Dead Sea Scrolls (ETCBC/dss, Abegg–Bowley–Cook): major non-biblical works " <>
        "and the biblical manuscripts' readings, Hebrew and Aramaic only",
    tables: ~w(ancient_source_passages ancient_source_passages_fts
               ancient_source_biblical_links ancient_source_notes
               dss_biblical_manuscripts dss_biblical_verses)
  }

  # The ancient pack's schema (studybible-mcp database.py), unchanged.
  @schema [
    """
    CREATE TABLE ancient_source_passages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      corpus TEXT NOT NULL,
      author TEXT NOT NULL,
      work_key TEXT NOT NULL,
      work_title TEXT NOT NULL,
      reference TEXT NOT NULL,
      alternate_reference TEXT,
      book_number INTEGER NOT NULL,
      section_number TEXT NOT NULL,
      section_end INTEGER NOT NULL,
      editorial_heading TEXT,
      text TEXT NOT NULL,
      original_text TEXT,
      period_tags TEXT NOT NULL,
      edition TEXT NOT NULL,
      translation TEXT,
      license TEXT NOT NULL,
      source_url TEXT NOT NULL,
      collection TEXT,
      sort_start INTEGER,
      sort_end INTEGER,
      original_language TEXT,
      original_license TEXT,
      translation_license TEXT,
      UNIQUE(corpus, work_key, reference)
    )
    """,
    """
    CREATE VIRTUAL TABLE ancient_source_passages_fts USING fts5(
      passage_id UNINDEXED,
      work_title UNINDEXED,
      reference UNINDEXED,
      text,
      original_text_folded,
      original_prefix_variants,
      tokenize = 'porter unicode61 remove_diacritics 2'
    )
    """,
    """
    CREATE TABLE ancient_source_biblical_links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      passage_id INTEGER NOT NULL REFERENCES ancient_source_passages(id),
      biblical_book TEXT NOT NULL,
      sort_start INTEGER NOT NULL,
      sort_end INTEGER NOT NULL,
      relationship_note TEXT NOT NULL,
      relation TEXT NOT NULL DEFAULT 'shared_tradition',
      UNIQUE(passage_id, biblical_book, sort_start, sort_end)
    )
    """,
    """
    CREATE TABLE ancient_source_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      passage_id INTEGER NOT NULL REFERENCES ancient_source_passages(id),
      corpus TEXT NOT NULL,
      work_key TEXT NOT NULL,
      citation TEXT NOT NULL,
      sort_start INTEGER NOT NULL,
      sort_end INTEGER NOT NULL,
      kind TEXT NOT NULL,
      note TEXT NOT NULL,
      contrast TEXT NOT NULL DEFAULT '',
      aligned TEXT NOT NULL DEFAULT '',
      UNIQUE(passage_id, citation, kind, note)
    )
    """,
    """
    CREATE TABLE dss_biblical_manuscripts (
      siglum TEXT PRIMARY KEY,
      name TEXT,
      site TEXT NOT NULL,
      books TEXT NOT NULL,
      verses INTEGER NOT NULL,
      reconstructed_only INTEGER NOT NULL,
      sort_order INTEGER NOT NULL
    )
    """,
    """
    CREATE TABLE dss_biblical_verses (
      reference TEXT NOT NULL,
      book TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      source_reference TEXT NOT NULL,
      mt_verse INTEGER NOT NULL,
      siglum TEXT NOT NULL REFERENCES dss_biblical_manuscripts(siglum),
      occurrence INTEGER NOT NULL,
      locator TEXT NOT NULL,
      text TEXT NOT NULL,
      letters INTEGER NOT NULL,
      preserved_letters INTEGER NOT NULL,
      language TEXT NOT NULL,
      PRIMARY KEY (reference, siglum, occurrence)
    )
    """,
    "CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID",
    "CREATE INDEX idx_asp_corpus_period ON ancient_source_passages(corpus, period_tags)",
    "CREATE INDEX idx_asp_locator ON ancient_source_passages(corpus, work_key, sort_start, sort_end)",
    """
    CREATE INDEX idx_asp_reference
    ON ancient_source_passages(corpus, work_key, book_number, section_number)
    """,
    """
    CREATE INDEX idx_asbl_biblical
    ON ancient_source_biblical_links(biblical_book, sort_start, sort_end)
    """,
    "CREATE INDEX idx_asn_locator ON ancient_source_notes(corpus, work_key, sort_start, sort_end)",
    "CREATE INDEX idx_asn_passage ON ancient_source_notes(passage_id)",
    "CREATE INDEX idx_dbv_verse ON dss_biblical_verses(book, chapter, verse)"
  ]

  @passage_columns ~w(id corpus author work_key work_title reference alternate_reference
                      book_number section_number section_end editorial_heading text original_text
                      period_tags edition translation license source_url collection sort_start
                      sort_end original_language original_license translation_license)a
  @fts_columns ~w(passage_id work_title reference text original_text_folded original_prefix_variants)a
  @manuscript_columns ~w(siglum name site books verses reconstructed_only sort_order)a
  @verse_columns ~w(reference book chapter verse source_reference mt_verse siglum occurrence locator text
                    letters preserved_letters language)a

  @doc "The pack's name, description and tables."
  @spec pack() :: map()
  def pack, do: @pack

  @doc "The CREATE statements, in order."
  @spec schema() :: [String.t()]
  def schema, do: @schema

  @doc """
  Writes `path` with `passages` (`Bezalel.Data.Scrolls.passages/3` rows, given
  ids 1, 2, … in order, each indexed for search), the biblical
  `manuscripts` and `verses` (`Bezalel.Data.Scrolls.biblical/3`) and `meta`.
  """
  @spec write(Path.t(), [map()], [map()], [map()], %{String.t() => String.t()}) :: :ok
  def write(path, passages, manuscripts, verses, meta) do
    passages =
      passages |> Enum.with_index(1) |> Enum.map(fn {row, id} -> Map.put(row, :id, id) end)

    Pack.build(path, @pack, @schema, meta, fn conn ->
      Pack.insert!(conn, "ancient_source_passages", @passage_columns, passages, fn row ->
        Enum.map(@passage_columns, &Map.fetch!(row, &1))
      end)

      Pack.insert!(conn, "ancient_source_passages_fts", @fts_columns, passages, &fts_values/1)

      Pack.insert!(conn, "dss_biblical_manuscripts", @manuscript_columns, manuscripts, fn row ->
        Enum.map(@manuscript_columns, &Map.fetch!(row, &1))
      end)

      Pack.insert!(conn, "dss_biblical_verses", @verse_columns, verses, fn row ->
        Enum.map(@verse_columns, &Map.fetch!(row, &1))
      end)

      Pack.exec!(
        conn,
        "INSERT INTO ancient_source_passages_fts(ancient_source_passages_fts) VALUES('optimize')"
      )
    end)
  end

  @doc "A passage's search-index row: its folded text and Hebrew prefix variants."
  @spec fts_values(map()) :: list()
  def fts_values(row) do
    original = row.original_text || ""

    [
      row.id,
      row.work_title,
      row.reference,
      row.text,
      Scrolls.index_text(original),
      Scrolls.prefix_variants(original)
    ]
  end
end
