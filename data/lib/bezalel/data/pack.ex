defmodule Bezalel.Data.Pack do
  @moduledoc """
  Writes the `translations` pack, following the conventions of the phone
  app's `data/scripts/make_packs.py`: a standalone SQLite file with page size
  4096, rows inserted in canonical order, ANALYZE statistics, VACUUMed,
  `PRAGMA integrity_check` must say ok, and a `pack_meta(key, value)` table.
  """

  alias Exqlite.Sqlite3

  @name "translations"
  @description "Bible translations (English verse texts other than the BSB): the NET Bible"
  @tables ~w(translations translation_verses)

  @schema [
    """
    CREATE TABLE translations (
      key TEXT PRIMARY KEY,
      name TEXT,
      abbreviation TEXT,
      url TEXT,
      copyright TEXT,
      licence TEXT,
      source_url TEXT,
      source_sha256 TEXT
    )
    """,
    """
    CREATE TABLE translation_verses (
      translation TEXT NOT NULL,
      reference TEXT NOT NULL,
      book TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      text TEXT NOT NULL,
      PRIMARY KEY (translation, reference)
    )
    """,
    "CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID"
  ]

  @translation_columns ~w(key name abbreviation url copyright licence source_url source_sha256)a
  @verse_columns ~w(reference book chapter verse text)a

  @doc "The pack's name, as in `Bezalel.Study.DB` (`translations.sqlite`)."
  @spec name() :: String.t()
  def name, do: @name

  @doc "The CREATE statements, in order."
  @spec schema() :: [String.t()]
  def schema, do: @schema

  @doc """
  Writes `path` (replacing it) with the `translations` rows (maps with the
  `translations` columns), the verse rows of each translation
  (`%{"net" => [row]}`) and `meta`, merged over the `pack_meta` keys every
  pack has (`pack`, `description`, `tables`, `sqlite_version`).
  """
  @spec write(Path.t(), [map()], %{String.t() => [map()]}, %{String.t() => String.t()}) :: :ok
  def write(path, translations, verses, meta) do
    File.mkdir_p!(Path.dirname(path))
    File.rm(path)
    {:ok, conn} = Sqlite3.open(path)

    try do
      Enum.each(
        ["PRAGMA page_size = 4096", "PRAGMA journal_mode = OFF", "PRAGMA synchronous = OFF"],
        &exec!(conn, &1)
      )

      exec!(conn, "BEGIN")
      Enum.each(@schema, &exec!(conn, &1))

      insert!(conn, "translations", @translation_columns, translations, fn translation ->
        Enum.map(@translation_columns, &Map.fetch!(translation, &1))
      end)

      for {key, rows} <- Enum.sort(verses) do
        columns = [:translation | @verse_columns]

        insert!(conn, "translation_verses", columns, rows, fn row ->
          [key | Enum.map(@verse_columns, &Map.fetch!(row, &1))]
        end)
      end

      meta =
        Map.merge(meta, %{
          "pack" => @name,
          "description" => @description,
          "tables" => Enum.join(@tables, " "),
          "sqlite_version" => sqlite_version(conn)
        })

      insert!(conn, "pack_meta", [:key, :value], Enum.sort(meta), &Tuple.to_list/1)
      exec!(conn, "COMMIT")
      exec!(conn, "ANALYZE")
      exec!(conn, "VACUUM")

      case query(conn, "PRAGMA integrity_check") do
        [["ok"]] -> :ok
        other -> raise "#{path}: integrity_check #{inspect(other)}"
      end
    after
      Sqlite3.close(conn)
    end
  end

  @doc "Runs `sql` with `args` on a read-only connection to `path` and returns the rows."
  @spec read(Path.t(), String.t(), list()) :: [list()]
  def read(path, sql, args \\ []) do
    unless File.regular?(path), do: raise(ArgumentError, "#{path} does not exist")
    {:ok, conn} = Sqlite3.open(path, mode: :readonly)

    try do
      query(conn, sql, args)
    after
      Sqlite3.close(conn)
    end
  end

  defp sqlite_version(conn) do
    [[version]] = query(conn, "SELECT sqlite_version()")
    version
  end

  defp query(conn, sql, args \\ []) do
    {:ok, statement} = Sqlite3.prepare(conn, sql)

    try do
      :ok = Sqlite3.bind(statement, args)
      {:ok, rows} = Sqlite3.fetch_all(conn, statement)
      rows
    after
      Sqlite3.release(conn, statement)
    end
  end

  defp insert!(conn, table, columns, rows, values) do
    placeholders = Enum.map_join(columns, ", ", fn _column -> "?" end)
    sql = "INSERT INTO #{table} (#{Enum.join(columns, ", ")}) VALUES (#{placeholders})"
    {:ok, statement} = Sqlite3.prepare(conn, sql)

    try do
      Enum.each(rows, fn row ->
        :ok = Sqlite3.bind(statement, values.(row))
        :done = Sqlite3.step(conn, statement)
        :ok = Sqlite3.reset(statement)
      end)
    after
      Sqlite3.release(conn, statement)
    end
  end

  defp exec!(conn, sql) do
    case Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> raise "SQLite: #{reason} in #{sql}"
    end
  end
end
