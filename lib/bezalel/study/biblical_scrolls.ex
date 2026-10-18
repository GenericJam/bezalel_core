defmodule Bezalel.Study.BiblicalScrolls do
  @moduledoc """
  The biblical Dead Sea Scrolls' readings in the scrolls pack
  (`dss_biblical_verses`, `dss_biblical_manuscripts`; built by `data/`'s
  `mix bezalel.data.scrolls` from ETCBC/dss): what each manuscript has at a
  verse, keyed by the packs' English reference (`Deu.32.8`), with its
  siglum, conventional name, fragment and line locator, text (`[ ]` modern
  reconstruction, ` / ` a line break) and how many of its letters survive
  outside reconstruction.

  `compare_biblical_versions` shows them as its `DSS` witnesses beside the
  MT and LXX (the source `manuscripts:dss`, `Bezalel.Study.Sources`).
  """

  alias Bezalel.Study.DB

  @edition "Dead Sea Scrolls"
  @license "CC BY-NC 4.0"
  @transcription "Abegg–Bowley–Cook transcription (ETCBC/dss Text-Fabric 2.0.1)"

  @type reading :: %{
          reference: String.t(),
          book: String.t(),
          chapter: integer(),
          verse: integer(),
          source_reference: String.t(),
          mt_verse: boolean(),
          siglum: String.t(),
          name: String.t() | nil,
          site: String.t(),
          occurrence: pos_integer(),
          locator: String.t(),
          text: String.t(),
          language: String.t(),
          letters: non_neg_integer(),
          preserved_letters: non_neg_integer(),
          sort_order: pos_integer()
        }

  @doc "The edition label of every reading."
  @spec edition() :: String.t()
  def edition, do: @edition

  @doc "The readings' licence."
  @spec license() :: String.t()
  def license, do: @license

  @doc "The transcription the readings are from."
  @spec transcription() :: String.t()
  def transcription, do: @transcription

  @doc """
  The readings of `book` from `{chapter, verse}` `start` to `finish`
  (English numbering, inclusive), in verse then manuscript order.
  """
  @spec range(DB.conn(), String.t(), {integer(), integer()}, {integer(), integer()}) ::
          [reading()]
  def range(conn, book, {chapter, verse}, {end_chapter, end_verse}) do
    conn
    |> DB.all(
      """
      #{select()}
      WHERE v.book = ? AND (v.chapter, v.verse) BETWEEN (?, ?) AND (?, ?)
      ORDER BY v.chapter, v.verse, m.sort_order, v.occurrence
      """,
      [book, chapter, verse, end_chapter, end_verse]
    )
    |> Enum.map(&reading/1)
  end

  @doc "The readings of the verses `references` ('Deu.32.8'), in the order given, then manuscript order."
  @spec at(DB.conn(), [String.t()]) :: [reading()]
  def at(_conn, []), do: []

  def at(conn, references) do
    order = references |> Enum.with_index() |> Map.new()

    conn
    |> DB.all(
      "#{select()} WHERE v.reference IN (#{DB.placeholders(references)})",
      references
    )
    |> Enum.map(&reading/1)
    |> Enum.sort_by(&{order[&1.reference], &1.sort_order, &1.occurrence})
  end

  @doc "`:ok` if the pack's biblical tables can be read, else the damaged-pack error."
  @spec check(DB.conn()) :: :ok | {:error, String.t()}
  def check(conn),
    do: DB.check_tables(conn, :scrolls, ["dss_biblical_verses", "dss_biblical_manuscripts"])

  @doc "The ETCBC/dss source the pack was built from (its `pack_meta` `dss_source`), or nil."
  @spec source_url(DB.conn()) :: String.t() | nil
  def source_url(conn) do
    case DB.one(conn, "SELECT value FROM pack_meta WHERE key = 'dss_source'") do
      %{"value" => url} -> url
      nil -> nil
    end
  end

  defp select do
    """
    SELECT v.reference, v.book, v.chapter, v.verse, v.source_reference, v.mt_verse,
           v.siglum, m.name, m.site, v.occurrence, v.locator, v.text, v.language,
           v.letters, v.preserved_letters, m.sort_order
    FROM dss_biblical_verses v JOIN dss_biblical_manuscripts m ON m.siglum = v.siglum
    """
  end

  defp reading(row) do
    %{
      reference: row["reference"],
      book: row["book"],
      chapter: row["chapter"],
      verse: row["verse"],
      source_reference: row["source_reference"],
      mt_verse: row["mt_verse"] == 1,
      siglum: row["siglum"],
      name: row["name"],
      site: row["site"],
      occurrence: row["occurrence"],
      locator: row["locator"],
      text: row["text"],
      language: row["language"],
      letters: row["letters"],
      preserved_letters: row["preserved_letters"],
      sort_order: row["sort_order"]
    }
  end
end
