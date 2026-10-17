defmodule Bezalel.Study.Graph do
  @moduledoc """
  Queries and Markdown shared by the graph tools (the graph pack: the
  Theographic Bible Metadata's people, places, events and family edges).

  Ported from studybible-mcp's `database.py` (`graph_find_person`,
  `graph_get_family`) and `tools.py` (`format_year`, `_mermaid_id`) (MIT).
  """

  alias Bezalel.Study.DB

  @typedoc "A person or place by graph id and name."
  @type entity :: %{id: String.t(), name: String.t()}

  @typedoc "A person's parents and children (with the relationship), spouses and siblings."
  @type family :: %{
          parents: [%{id: String.t(), name: String.t(), relationship: String.t()}],
          children: [%{id: String.t(), name: String.t(), relationship: String.t()}],
          partners: [entity()],
          siblings: [entity()]
        }

  @doc """
  The person `name` names: an exact name first, then the one with the most
  aliases, then the most family edges; nil when none matches.
  """
  @spec find_person(DB.conn(), String.t()) :: DB.row() | nil
  def find_person(conn, name) do
    DB.one(
      conn,
      """
      SELECT p.* FROM graph_people p
      LEFT JOIN (
          SELECT from_person_id as pid, COUNT(*) as cnt FROM graph_family_edges GROUP BY from_person_id
          UNION ALL
          SELECT to_person_id, COUNT(*) FROM graph_family_edges GROUP BY to_person_id
      ) fe ON fe.pid = p.id
      WHERE LOWER(p.name) = LOWER(?)
         OR LOWER(p.also_called) LIKE LOWER(?)
      GROUP BY p.id
      ORDER BY
          CASE WHEN LOWER(p.name) = LOWER(?) THEN 0 ELSE 1 END,
          LENGTH(COALESCE(p.also_called, '')) DESC,
          COALESCE(SUM(fe.cnt), 0) DESC
      LIMIT 10
      """,
      [name, "%#{name}%", name]
    )
  end

  @doc "The immediate family of person `id`."
  @spec family(DB.conn(), String.t()) :: family()
  def family(conn, id) do
    %{
      parents:
        conn
        |> DB.all(
          """
          SELECT p.id, p.name, e.relationship_type FROM graph_family_edges e
          JOIN graph_people p ON p.id = e.from_person_id
          WHERE e.to_person_id = ?
            AND e.relationship_type IN ('father_of', 'mother_of')
          """,
          [id]
        )
        |> Enum.map(&relative/1),
      children:
        conn
        |> DB.all(
          """
          SELECT p.id, p.name, e.relationship_type FROM graph_family_edges e
          JOIN graph_people p ON p.id = e.to_person_id
          WHERE e.from_person_id = ?
            AND e.relationship_type IN ('father_of', 'mother_of')
          """,
          [id]
        )
        |> Enum.map(&relative/1),
      partners: related(conn, id, "partner_of"),
      siblings: related(conn, id, "sibling_of")
    }
  end

  defp relative(row),
    do: %{id: row["id"], name: row["name"], relationship: row["relationship_type"]}

  defp related(conn, id, relationship) do
    conn
    |> DB.all(
      """
      SELECT p.id, p.name FROM graph_family_edges e
      JOIN graph_people p ON p.id = CASE
          WHEN e.from_person_id = ? THEN e.to_person_id
          ELSE e.from_person_id END
      WHERE (e.from_person_id = ? OR e.to_person_id = ?)
        AND e.relationship_type = ?
      """,
      [id, id, id, relationship]
    )
    |> Enum.map(&entity/1)
  end

  @doc "A row's id and name."
  @spec entity(DB.row()) :: entity()
  def entity(row), do: %{id: row["id"], name: row["name"]}

  @doc "A year as '1995 BC' or 'AD 30'; nil is 'unknown'."
  @spec year(integer() | nil) :: String.t()
  def year(nil), do: "unknown"
  def year(year) when year < 0, do: "#{-year} BC"
  def year(year), do: "AD #{year}"

  @doc "' (1995 BC)' for a known year (not 0, as Python's truthiness), else ''."
  @spec year_suffix(integer() | nil) :: String.t()
  def year_suffix(year) when year in [nil, 0], do: ""
  def year_suffix(year), do: " (#{year(year)})"

  @doc "A Mermaid node id for a name: spaces as underscores, no quotes or parentheses."
  @spec mermaid_id(String.t()) :: String.t()
  def mermaid_id(name) do
    name
    |> String.replace(" ", "_")
    |> String.replace(["'", "(", ")"], "")
  end

  @doc "The first `count` code points of `text` (Python's `text[:count]`)."
  @spec take(String.t(), non_neg_integer()) :: String.t()
  def take(text, count), do: text |> String.codepoints() |> Enum.take(count) |> Enum.join()
end
