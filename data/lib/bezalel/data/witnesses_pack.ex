defmodule Bezalel.Data.WitnessesPack do
  @moduledoc """
  Writes the `witnesses` pack (`Bezalel.Data.Pack.build/5`): each source in
  tables of its own, so its licence stays with its rows, and
  `witness_sources` naming each source's tables, licence, attribution and
  pinned source:

    * `sp_verses`: the Samaritan Pentateuch (CC BY-NC 4.0);
    * `sblgnt_verses`, `sblgnt_apparatus`: the SBL Greek New Testament and
      its apparatus (CC BY 4.0);
    * `hottp_entries`, `hottp_alternatives`, `hottp_verses`,
      `hottp_ratings`, `hottp_factors`: the UBS Hebrew Old Testament Text
      Project (CC BY-SA 4.0).

  Lists (sigla, variants, factors, renderings, segments) are JSON arrays.
  """

  alias Bezalel.Data.Pack

  @pack %{
    name: "witnesses",
    description:
      "Textual witnesses: the Samaritan Pentateuch, the SBL Greek New Testament with its " <>
        "apparatus, and the UBS Hebrew Old Testament Text Project",
    tables: ~w(witness_sources sp_verses sblgnt_verses sblgnt_apparatus hottp_entries
               hottp_alternatives hottp_verses hottp_ratings hottp_factors)
  }

  @schema [
    """
    CREATE TABLE witness_sources (
      key TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      tables TEXT NOT NULL,
      licence TEXT NOT NULL,
      licence_url TEXT NOT NULL,
      attribution TEXT NOT NULL,
      source_url TEXT NOT NULL,
      source_sha256 TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE sp_verses (
      reference TEXT NOT NULL,
      book TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      source_reference TEXT PRIMARY KEY,
      mt_verse INTEGER NOT NULL,
      text TEXT NOT NULL,
      words INTEGER NOT NULL,
      note TEXT
    )
    """,
    "CREATE INDEX sp_verses_position ON sp_verses (book, chapter, verse)",
    """
    CREATE TABLE sblgnt_verses (
      reference TEXT PRIMARY KEY,
      book TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      text TEXT NOT NULL,
      file TEXT NOT NULL,
      line INTEGER NOT NULL
    )
    """,
    "CREATE INDEX sblgnt_verses_position ON sblgnt_verses (book, chapter, verse)",
    """
    CREATE TABLE sblgnt_apparatus (
      reference TEXT NOT NULL,
      book TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      unit INTEGER NOT NULL,
      verses TEXT,
      note TEXT NOT NULL,
      parsed INTEGER NOT NULL,
      lemma TEXT,
      lemma_sigla TEXT,
      variants TEXT,
      file TEXT NOT NULL,
      line INTEGER NOT NULL,
      PRIMARY KEY (reference, unit)
    )
    """,
    "CREATE INDEX sblgnt_apparatus_position ON sblgnt_apparatus (book, chapter, verse)",
    """
    CREATE TABLE hottp_entries (
      id TEXT PRIMARY KEY,
      remark TEXT,
      suggestion TEXT,
      line INTEGER NOT NULL
    )
    """,
    """
    CREATE TABLE hottp_alternatives (
      entry_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      hebrew TEXT,
      rating TEXT,
      grade TEXT,
      factors TEXT NOT NULL,
      literal TEXT,
      renderings TEXT NOT NULL,
      PRIMARY KEY (entry_id, position)
    )
    """,
    """
    CREATE TABLE hottp_verses (
      reference TEXT NOT NULL,
      entry_id TEXT NOT NULL,
      book TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      source_reference TEXT NOT NULL,
      mt_verse INTEGER NOT NULL,
      segments TEXT NOT NULL,
      PRIMARY KEY (entry_id, source_reference)
    )
    """,
    "CREATE INDEX hottp_verses_position ON hottp_verses (book, chapter, verse)",
    "CREATE TABLE hottp_ratings (grade TEXT PRIMARY KEY, meaning TEXT NOT NULL)",
    """
    CREATE TABLE hottp_factors (
      number INTEGER PRIMARY KEY,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      explanation TEXT NOT NULL
    )
    """,
    "CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID"
  ]

  @columns %{
    "witness_sources" =>
      ~w(key name tables licence licence_url attribution source_url source_sha256)a,
    "sp_verses" => ~w(reference book chapter verse source_reference mt_verse text words note)a,
    "sblgnt_verses" => ~w(reference book chapter verse text file line)a,
    "sblgnt_apparatus" =>
      ~w(reference book chapter verse unit verses note parsed lemma lemma_sigla variants file line)a,
    "hottp_entries" => ~w(id remark suggestion line)a,
    "hottp_alternatives" => ~w(entry_id position hebrew rating grade factors literal renderings)a,
    "hottp_verses" =>
      ~w(reference entry_id book chapter verse source_reference mt_verse segments)a,
    "hottp_ratings" => ~w(grade meaning)a,
    "hottp_factors" => ~w(number kind name explanation)a
  }

  @json ~w(lemma_sigla variants factors renderings segments)a

  # The rows the tests read (`cut/3`): verses the core fixture has (Gen 1,
  # Exo 31, John 3, Col 1) and the ones the tools' examples name (Gen 4:8,
  # John 1:18, Mark 1:1, 1 Sam 1:24, Deut 32:8), and one of each kind the
  # tools handle: a renumbered SP verse (Exo 8:1, Hebrew 7:26), a grouped
  # one (Exo 26:35), two SP verses under one English verse (Num 26:1), a
  # renumbered HOTTP verse (Exo 8:3, Hebrew 7:28), apparatus units spanning
  # verses (Luke 22:43), with WH's double brackets, and the unparsed note
  # (John 7:52).
  @fixture_verses ~w(Gen.1.1 Gen.1.2 Gen.1.3 Gen.1.6 Gen.1.7 Gen.4.8 Gen.30.36 Exo.8.1
                     Exo.8.3 Exo.26.35 Exo.31.1 Exo.31.2 Exo.31.3 Num.26.1 Deu.32.8 Deu.32.43
                     1Sa.1.24 Mrk.1.1 Luk.22.43 Jhn.1.18 Jhn.3.13 Jhn.3.16 Jhn.3.17 Jhn.7.52
                     Col.1.11 Col.1.12)

  @doc "The pack's name, description and tables."
  @spec pack() :: map()
  def pack, do: @pack

  @doc "The columns written to each table, in order."
  @spec columns() :: %{String.t() => [atom()]}
  def columns, do: @columns

  @doc """
  Writes `path` with `tables` (table name → rows, maps with the table's
  `columns/0`; list columns are written as JSON, booleans as 0/1) and `meta`.
  """
  @spec write(Path.t(), %{String.t() => [map()]}, %{String.t() => String.t()}) :: :ok
  def write(path, tables, meta) do
    Pack.build(path, @pack, @schema, meta, fn conn ->
      Enum.each(@pack.tables, &insert_table!(conn, &1, Map.get(tables, &1, [])))
    end)
  end

  defp insert_table!(conn, table, rows) do
    columns = Map.fetch!(@columns, table)
    values = fn row -> Enum.map(columns, &value(&1, Map.fetch!(row, &1))) end
    Pack.insert!(conn, table, columns, rows, values)
  end

  defp value(column, list) when column in @json and is_list(list), do: Jason.encode!(list)
  defp value(_column, true), do: 1
  defp value(_column, false), do: 0
  defp value(_column, value), do: value

  @doc """
  Cuts the test fixture at `out` from the pack at `from`: the rows of
  `@fixture_verses` in every verse table, the HOTTP entries and
  alternatives they name, the glossaries and sources whole, and `meta`.
  Returns the rows written per table.
  """
  @spec cut(Path.t(), Path.t(), %{String.t() => String.t()}) :: [{String.t(), non_neg_integer()}]
  def cut(from, out, meta) do
    read = fn table, where, args ->
      columns = Map.fetch!(@columns, table)

      from
      |> Pack.read(
        "SELECT #{Enum.join(columns, ", ")} FROM #{table} #{where} ORDER BY rowid",
        args
      )
      |> Enum.map(&(columns |> Enum.zip(&1) |> Map.new()))
    end

    in_verses = "WHERE reference IN (#{placeholders(@fixture_verses)})"
    verses = read.("hottp_verses", in_verses, @fixture_verses)
    ids = verses |> Enum.map(& &1.entry_id) |> Enum.uniq()
    in_ids = fn column -> "WHERE #{column} IN (#{placeholders(ids)})" end

    tables = %{
      "witness_sources" => read.("witness_sources", "", []),
      "sp_verses" => read.("sp_verses", in_verses, @fixture_verses),
      "sblgnt_verses" => read.("sblgnt_verses", in_verses, @fixture_verses),
      "sblgnt_apparatus" => read.("sblgnt_apparatus", in_verses, @fixture_verses),
      "hottp_entries" => read.("hottp_entries", in_ids.("id"), ids),
      "hottp_alternatives" => read.("hottp_alternatives", in_ids.("entry_id"), ids),
      "hottp_verses" => verses,
      "hottp_ratings" => read.("hottp_ratings", "", []),
      "hottp_factors" => read.("hottp_factors", "", [])
    }

    write(out, tables, meta)
    Enum.map(@pack.tables, &{&1, length(tables[&1])})
  end

  defp placeholders(values), do: Enum.map_join(values, ", ", fn _ -> "?" end)
end
