defmodule Bezalel.Study.Tools.GraphEnrichedSearch do
  @moduledoc """
  `graph_enriched_search`: one verse's text with the people, places and
  events it mentions and each person's immediate family (the graph pack,
  and the core pack for the text).

  Ported from studybible-mcp's `handle_graph_enriched_search`,
  `graph_get_verse_entities` and `format_enriched_verse` (MIT). Same text,
  including that a person's family is that of the person `explore_genealogy`
  would pick for the mentioned name (not necessarily the namesake the verse
  means); a mention without a name shows its id instead of "None". A verse
  not in the pack still lists the verse's entities (there are none for a
  reference that isn't a verse). `result/1` returns the verse and the
  entities, each person with their family.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Graph, Reference, Verses}

  @impl true
  def name, do: "graph_enriched_search"

  @impl true
  def description do
    """
    Retrieve a comprehensive enriched view of a single verse: its text plus all people, places, events, and family relationships.

    Returns the verse text, the people, places, and events mentioned in it, and the
    family relationships of each person found. For 'Matthew 1:1' that is the verse
    text, Jesus, David, and Abraham with their relationships, and the associated
    places and events.

    Combines what `lookup_verse` and `people_in_passage` return separately. Verse
    level only; `people_in_passage` also accepts chapters but returns entity lists
    without verse text or relationships.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "reference" => %{
          "type" => "string",
          "description" => "Bible verse reference (e.g., 'Genesis 22:1', 'Matthew 1:1')"
        }
      },
      "required" => ["reference"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc "A person mentioned, with the family of the person their name finds (nil if none)."
  @type person :: %{id: String.t(), name: String.t(), family: Graph.family() | nil}

  @type t :: %{
          reference: String.t(),
          verse: Format.verse_view() | nil,
          people: [person()],
          places: [Graph.entity()],
          events: [Graph.entity()]
        }

  @doc "The verse and entities of `args`' reference (either possibly missing)."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    case Args.reference(args) do
      "" ->
        {:error, "Please provide a verse reference (e.g., 'Genesis 22:1')."}

      reference ->
        with {:ok, entities} <- DB.with_pack(:graph, &entities(&1, reference)),
             {:ok, row} <- DB.with_pack(:core, &Verses.get(&1, reference)) do
          {:ok,
           Map.merge(entities, %{reference: reference, verse: row && Format.verse_view(row)})}
        end
    end
  end

  defp entities(conn, reference) do
    rows =
      DB.all(
        conn,
        """
        SELECT vm.entity_type, vm.entity_id,
               COALESCE(p.name, pl.name, e.title) as entity_name
        FROM graph_verse_mentions vm
        LEFT JOIN graph_people p ON vm.entity_type = 'person' AND p.id = vm.entity_id
        LEFT JOIN graph_places pl ON vm.entity_type = 'place' AND pl.id = vm.entity_id
        LEFT JOIN graph_events e ON vm.entity_type = 'event' AND e.id = vm.entity_id
        WHERE vm.verse_ref = ?
        """,
        [reference |> Reference.normalize() |> Reference.theographic()]
      )

    of_type = fn type ->
      for row <- rows, row["entity_type"] == type do
        %{id: row["entity_id"], name: row["entity_name"]}
      end
    end

    # Python keys the families by name, so namesakes in one verse share one.
    families =
      for %{name: name} <- of_type.("person"), name != nil, uniq: true, into: %{} do
        person = Graph.find_person(conn, name)
        {name, person && Graph.family(conn, person["id"])}
      end

    %{
      people:
        for(
          p <- of_type.("person"),
          do: %{id: p.id, name: p.name || p.id, family: p.name && families[p.name]}
        ),
      places: Enum.map(of_type.("place"), &%{&1 | name: &1.name || &1.id}),
      events: Enum.map(of_type.("event"), &%{&1 | name: &1.name || &1.id})
    }
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{
        reference: reference,
        verse: verse,
        people: people,
        places: places,
        events: events
      }) do
    verse_lines =
      case verse do
        nil ->
          []

        view ->
          [view.english, ""] ++
            if(view.original != "", do: ["**Original**: #{view.original}", ""], else: [])
      end

    people_lines =
      if people == [],
        do: [],
        else: ["### People Mentioned" | Enum.flat_map(people, &person_lines/1)] ++ [""]

    lines =
      ["## #{reference}#{Format.bsb_label(List.wrap(verse))}\n"] ++
        verse_lines ++
        people_lines ++
        list("Places Mentioned", places) ++
        list("Events", events) ++
        if(people == [] and places == [] and events == [],
          do: ["*No entity data available for this verse in the Theographic database.*\n"],
          else: []
        )

    Enum.join(lines, "\n")
  end

  defp person_lines(%{name: name, family: family}) do
    parts =
      if family do
        {shown, rest} = Enum.split(family.children, 5)
        more = if rest == [], do: "", else: " (+#{length(rest)} more)"

        Enum.reject(
          [
            family.parents != [] && "Parents: #{names(family.parents)}",
            family.partners != [] && "Spouse: #{names(family.partners)}",
            shown != [] && "Children: #{names(shown)}#{more}"
          ],
          &(&1 == false)
        )
      else
        []
      end

    ["\n**#{name}**"] ++ if(parts == [], do: [], else: ["  " <> Enum.join(parts, " | ")])
  end

  defp names(people), do: Enum.map_join(people, ", ", & &1.name)

  defp list(_heading, []), do: []

  defp list(heading, entities),
    do: ["### #{heading}" | Enum.map(entities, &"- **#{&1.name}**")] ++ [""]
end
