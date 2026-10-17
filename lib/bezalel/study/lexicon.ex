defmodule Bezalel.Study.Lexicon do
  @moduledoc """
  Lexicon queries on the core pack: an entry by Strong's number and a
  search by English word, transliteration or concept.

  Ported from studybible-mcp's `database.py` (MIT): `_normalize_strongs`,
  `get_lexicon_entry`, `search_lexicon`.
  """

  alias Bezalel.Study.{DB, Patterns}

  @doc """
  A Strong's number in the packs' form: 'G26' is 'G0026', 'h430g' is
  'H0430G'. Anything else comes back upper-cased and trimmed.
  """
  @spec normalize_strongs(String.t()) :: String.t()
  def normalize_strongs(strongs) do
    strongs = strongs |> String.upcase() |> String.trim()

    case Regex.run(Patterns.get(:strongs), strongs) do
      [_, prefix, number, suffix] ->
        prefix <>
          String.pad_leading(Integer.to_string(String.to_integer(number)), 4, "0") <>
          suffix

      nil ->
        strongs
    end
  end

  @doc """
  The entry for a Strong's number, or nil. The lexicon is keyed by the bare
  number, so a sense-suffixed number (H0430G, from verse word data) falls
  back to it.
  """
  @spec entry(DB.conn(), String.t()) :: DB.row() | nil
  def entry(conn, strongs) do
    strongs = normalize_strongs(strongs)

    DB.one(conn, "SELECT * FROM lexicon WHERE strongs = ?", [strongs]) ||
      if Regex.match?(Patterns.get(:strongs_suffixed), strongs),
        do: DB.one(conn, "SELECT * FROM lexicon WHERE strongs = ?", [String.slice(strongs, 0, 5)])
  end

  @doc """
  Entries whose definition, transliteration or word contains `query`
  (ignoring case), at most `limit`; in `language` ("greek" or "hebrew") or
  both when nil. Entries matching in the gloss, word or transliteration
  come before those matching only in a long definition, then the most
  frequent words first.
  """
  @spec search(DB.conn(), String.t(), String.t() | nil, pos_integer()) :: [DB.row()]
  def search(conn, query, language, limit) do
    like = "%#{String.downcase(query)}%"

    {language_clause, language_params} =
      if language in [nil, ""],
        do: {"", []},
        else: {" AND language = ?", [String.downcase(language)]}

    DB.all(
      conn,
      """
      SELECT * FROM lexicon
      WHERE (
          LOWER(short_definition) LIKE ?
          OR LOWER(full_definition) LIKE ?
          OR LOWER(transliteration) LIKE ?
          OR LOWER(word) LIKE ?
          OR LOWER(abbott_smith_def) LIKE ?
      )#{language_clause}
      ORDER BY
          CASE WHEN LOWER(short_definition) LIKE ? OR LOWER(word) LIKE ?
                    OR LOWER(transliteration) LIKE ? THEN 0 ELSE 1 END,
          usage_count DESC, strongs
      LIMIT ?
      """,
      List.duplicate(like, 5) ++ language_params ++ List.duplicate(like, 3) ++ [limit]
    )
  end
end
