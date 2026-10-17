defmodule Bezalel.Study.Aquifer do
  @moduledoc """
  The BibleAquifer articles in the notes pack (`aquifer_content`) that
  `get_bible_dictionary` and `get_key_terms` search, and the Markdown both
  print.

  Ported from studybible-mcp (MIT): `StudyBibleDB._search_aquifer_by_type`
  (`database.py`) and `_format_content_items` (`tools.py`).
  """

  alias Bezalel.Study.{DB, Format}

  @typedoc "An article: its title and plain text."
  @type article :: %{title: String.t(), content: String.t()}

  @doc """
  The articles of `resource_type` whose title is `query` (any case), else
  the first ten whose title or text contains it, title matches first and
  shorter titles first.
  """
  @spec search(String.t(), String.t()) :: {:ok, [article()]} | {:error, String.t()}
  def search(resource_type, query) do
    exact = """
    SELECT title, content_plain FROM aquifer_content
    WHERE resource_type = ? AND LOWER(title) = LOWER(?)
    """

    like = """
    SELECT title, content_plain FROM aquifer_content
    WHERE resource_type = ?
      AND (LOWER(title) LIKE LOWER(?) OR LOWER(content_plain) LIKE LOWER(?))
    ORDER BY
      CASE WHEN LOWER(title) LIKE LOWER(?) THEN 0 ELSE 1 END,
      LENGTH(title)
    LIMIT 10
    """

    pattern = "%#{query}%"

    DB.with_pack(:notes, fn conn ->
      rows =
        case DB.all(conn, exact, [resource_type, query]) do
          [] -> DB.all(conn, like, [resource_type, pattern, pattern, pattern])
          rows -> rows
        end

      Enum.map(rows, &%{title: &1["title"], content: &1["content_plain"]})
    end)
  end

  @doc "Each article under its title, cut to `limit` characters with `note`."
  @spec render([article()], non_neg_integer(), String.t()) :: String.t()
  def render(articles, limit, note) do
    articles
    |> Enum.flat_map(fn article ->
      body =
        if Format.present?(article.content),
          do: [Format.truncate(article.content, limit, note)],
          else: []

      ["## #{article.title}", ""] ++ body ++ [""]
    end)
    |> Enum.join("\n")
  end
end
