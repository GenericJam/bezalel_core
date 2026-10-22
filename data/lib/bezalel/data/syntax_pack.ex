defmodule Bezalel.Data.SyntaxPack do
  @moduledoc """
  Writes the `syntax` pack (`Bezalel.Data.Pack.build/5`):

    * `syntax_editions`: the two MACULA editions read (WLC for the Old
      Testament, SBLGNT for the New), with the repo and commit each row's
      `source_files` are paths in, and the licence and attribution;
    * `syntax_verses`: one row per verse in the packs' English numbering,
      its clauses as JSON (`Bezalel.Data.Syntax`).
  """

  alias Bezalel.Data.Pack

  @pack %{
    name: "syntax",
    description:
      "Clause structure (Clear-Bible MACULA syntax trees of the WLC and the SBLGNT): " <>
        "each verse's clauses, their parts' roles and words",
    tables: ~w(syntax_editions syntax_verses)
  }

  @schema [
    "CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID",
    """
    CREATE TABLE syntax_editions (
      edition TEXT PRIMARY KEY,
      language TEXT NOT NULL,
      name TEXT NOT NULL,
      repo TEXT NOT NULL,
      commit_sha TEXT NOT NULL,
      licence TEXT NOT NULL,
      attribution TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE syntax_verses (
      reference TEXT PRIMARY KEY,
      book TEXT NOT NULL,
      chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL,
      edition TEXT NOT NULL REFERENCES syntax_editions (edition),
      source_reference TEXT NOT NULL,
      source_files TEXT NOT NULL,
      clauses TEXT NOT NULL
    )
    """,
    "CREATE INDEX syntax_verses_place ON syntax_verses (book, chapter, verse)"
  ]

  @edition_columns ~w(edition language name repo commit_sha licence attribution)a
  @verse_columns ~w(reference book chapter verse edition source_reference source_files clauses)a

  @doc "The pack's name, description and tables."
  @spec pack() :: map()
  def pack, do: @pack

  @doc "The CREATE statements, in order."
  @spec schema() :: [String.t()]
  def schema, do: @schema

  @doc "The columns of `syntax_editions` and `syntax_verses`, in order."
  @spec columns() :: %{editions: [atom()], verses: [atom()]}
  def columns, do: %{editions: @edition_columns, verses: @verse_columns}

  @doc """
  Writes the pack at `path`: `editions` and `verses` (maps with the
  columns' keys), `meta` the extra `pack_meta` rows.
  """
  @spec write(Path.t(), [map()], [map()], %{String.t() => String.t()}) :: :ok
  def write(path, editions, verses, meta) do
    Pack.build(path, @pack, @schema, meta, fn conn ->
      Pack.insert!(
        conn,
        "syntax_editions",
        @edition_columns,
        editions,
        &values(&1, @edition_columns)
      )

      Pack.insert!(conn, "syntax_verses", @verse_columns, verses, &values(&1, @verse_columns))
    end)
  end

  defp values(row, columns), do: Enum.map(columns, &Map.fetch!(row, &1))
end
