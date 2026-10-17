defmodule Bezalel.Study.Tools.PeopleInPassage do
  @moduledoc """
  `people_in_passage`: the people, places and events the Theographic Bible
  Metadata records for a chapter or verse (the graph pack).

  Ported from studybible-mcp's `handle_people_in_passage`,
  `graph_get_verse_entities`, `graph_get_chapter_entities` and
  `format_passage_entities` (MIT). Same text; an entity without a name
  shows its id. `result/1` returns the entities with their graph ids.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Reference}

  @impl true
  def name, do: "people_in_passage"

  @impl true
  def description do
    """
    List the people, places, and events mentioned in a Bible passage.

    Returns the entities recorded for a chapter or verse in the Theographic Bible
    Metadata — for example, Genesis 22 returns Abraham, Isaac, the angel of the LORD,
    and Moriah; Acts 15 returns Paul, Barnabas, James, Jerusalem, and Antioch.

    Relevant for establishing the cast and setting of a narrative passage. Related
    tools: `graph_enriched_search` is verse-level only but adds the verse text and
    family relationships for each person found.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "reference" => %{
          "type" => "string",
          "description" =>
            "Bible reference - chapter (e.g., 'Romans 8') or verse (e.g., 'Genesis 22:1')"
        }
      },
      "required" => ["reference"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc "An entity: its graph id ('bezaleel_490') and name."
  @type entity :: %{id: String.t(), name: String.t()}

  @type t :: %{
          reference: String.t(),
          people: [entity()],
          places: [entity()],
          events: [entity()]
        }

  @doc """
  The entities of `args`' chapter or verse (possibly none); a reference
  that is neither is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    reference = Args.reference(args)

    cond do
      reference == "" ->
        {:error, "Please provide a Bible reference (e.g., 'Romans 8' or 'Genesis 22:1')."}

      String.contains?(reference, ":") ->
        theographic = reference |> Reference.normalize() |> Reference.theographic()
        entities(reference, "vm.verse_ref = ?", theographic)

      chapter = Reference.single_chapter(reference) ->
        {book, number} = chapter
        entities(reference, "vm.verse_ref LIKE ?", "#{Reference.theographic(book)}.#{number}.%")

      true ->
        {:error,
         "Could not parse reference: #{reference}. Use 'Romans 8' or 'Genesis 22:1' format."}
    end
  end

  defp entities(reference, where, param) do
    sql = """
    SELECT DISTINCT vm.entity_type, vm.entity_id,
           COALESCE(p.name, pl.name, e.title) AS entity_name
    FROM graph_verse_mentions vm
    LEFT JOIN graph_people p ON vm.entity_type = 'person' AND p.id = vm.entity_id
    LEFT JOIN graph_places pl ON vm.entity_type = 'place' AND pl.id = vm.entity_id
    LEFT JOIN graph_events e ON vm.entity_type = 'event' AND e.id = vm.entity_id
    WHERE #{where}
    """

    with {:ok, rows} <- DB.with_pack(:graph, &DB.all(&1, sql, [param])) do
      {:ok,
       %{
         reference: reference,
         people: of_type(rows, "person"),
         places: of_type(rows, "place"),
         events: of_type(rows, "event")
       }}
    end
  end

  defp of_type(rows, type) do
    for row <- rows, row["entity_type"] == type do
      %{id: row["entity_id"], name: row["entity_name"] || row["entity_id"]}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(result) do
    sections =
      for {heading, entities} <- [
            {"People", result.people},
            {"Places", result.places},
            {"Events", result.events}
          ],
          entities != [] do
        ["### #{heading}" | Enum.map(entities, &"- **#{&1.name}**")] ++ [""]
      end

    lines =
      if sections == [],
        do: ["No entities found for this passage in the Theographic database.\n"],
        else: List.flatten(sections)

    Enum.join(["## Entities in #{result.reference}\n" | lines], "\n")
  end
end
