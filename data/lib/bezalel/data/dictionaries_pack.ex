defmodule Bezalel.Data.DictionariesPack do
  @moduledoc """
  Writes the `dictionaries` pack (`Bezalel.Data.Pack.build/5`): the UBS
  dictionaries (`Bezalel.Data.Dictionaries`), each with its licence and
  attribution in its `dictionaries` row; entries, their Strong's keys,
  meanings, the meanings' domains and the domain names.
  """

  alias Bezalel.Data.Pack

  @pack %{
    name: "dictionaries",
    description:
      "UBS dictionaries: the UBS Dictionary of Biblical Hebrew (from SDBH) and the UBS " <>
        "Dictionary of the Greek New Testament (from Louw & Nida): meanings, semantic " <>
        "domains, glosses",
    tables: ~w(dictionaries dictionary_entries dictionary_strongs dictionary_meanings
               dictionary_domains dictionary_meaning_domains)
  }

  @schema [
    """
    CREATE TABLE dictionaries (
      key TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      edition TEXT NOT NULL,
      language TEXT NOT NULL,
      source_url TEXT NOT NULL,
      source_sha256 TEXT NOT NULL,
      licence TEXT NOT NULL,
      licence_url TEXT NOT NULL,
      attribution TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE dictionary_entries (
      dictionary TEXT NOT NULL,
      entry_id TEXT NOT NULL,
      lemma TEXT NOT NULL,
      strong_codes TEXT NOT NULL,
      PRIMARY KEY (dictionary, entry_id)
    ) WITHOUT ROWID
    """,
    """
    CREATE TABLE dictionary_strongs (
      strongs TEXT NOT NULL,
      dictionary TEXT NOT NULL,
      entry_id TEXT NOT NULL,
      given TEXT NOT NULL,
      PRIMARY KEY (strongs, dictionary, entry_id)
    ) WITHOUT ROWID
    """,
    """
    CREATE TABLE dictionary_meanings (
      dictionary TEXT NOT NULL,
      entry_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      meaning_id TEXT NOT NULL,
      part_of_speech TEXT,
      louw_nida TEXT,
      definition TEXT,
      glosses TEXT NOT NULL,
      comments TEXT,
      reference_count INTEGER NOT NULL,
      PRIMARY KEY (dictionary, entry_id, position)
    ) WITHOUT ROWID
    """,
    """
    CREATE TABLE dictionary_domains (
      dictionary TEXT NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      level INTEGER NOT NULL,
      PRIMARY KEY (dictionary, code)
    ) WITHOUT ROWID
    """,
    """
    CREATE TABLE dictionary_meaning_domains (
      dictionary TEXT NOT NULL,
      meaning_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      position INTEGER NOT NULL,
      code TEXT NOT NULL,
      source_code TEXT,
      PRIMARY KEY (dictionary, meaning_id, kind, position)
    ) WITHOUT ROWID
    """,
    "CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID"
  ]

  @columns %{
    "dictionaries" =>
      ~w(key title edition language source_url source_sha256 licence licence_url attribution)a,
    "dictionary_entries" => ~w(dictionary entry_id lemma strong_codes)a,
    "dictionary_strongs" => ~w(strongs dictionary entry_id given)a,
    "dictionary_meanings" =>
      ~w(dictionary entry_id position meaning_id part_of_speech louw_nida definition glosses
         comments reference_count)a,
    "dictionary_domains" => ~w(dictionary code name level)a,
    "dictionary_meaning_domains" => ~w(dictionary meaning_id kind position code source_code)a
  }

  @doc "The pack's name, as in `Bezalel.Study.DB`."
  @spec name() :: String.t()
  def name, do: @pack.name

  @doc "Each table's columns, in order (atoms), as the rows' keys."
  @spec columns() :: %{String.t() => [atom()]}
  def columns, do: @columns

  @doc """
  Writes `path` (replacing it) with `rows` (`%{table => [row map]}`, the
  tables of `columns/0`) and `meta` over the keys every pack has.
  """
  @spec write(Path.t(), %{String.t() => [map()]}, %{String.t() => String.t()}) :: :ok
  def write(path, rows, meta) do
    Pack.build(path, @pack, @schema, meta, fn conn ->
      for table <- @pack.tables do
        columns = Map.fetch!(@columns, table)
        Pack.insert!(conn, table, columns, Map.fetch!(rows, table), &values(&1, columns))
      end
    end)
  end

  defp values(row, columns), do: Enum.map(columns, &Map.fetch!(row, &1))
end
