defmodule Bezalel.Study.Tools.ExplorePersonEvents do
  @moduledoc """
  `explore_person_events`: the recorded events of a person's life in
  chronological order, with their places and a Mermaid timeline (the graph
  pack).

  Ported from studybible-mcp's `handle_explore_person_events`,
  `graph_get_person_events`, `graph_get_event_places`,
  `format_person_events` and `mermaid_person_timeline` (MIT). Same text; an
  unknown person is an error. `result/1` returns the timeline: each event
  with its year and places.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Graph}

  @impl true
  def name, do: "explore_person_events"

  @impl true
  def description do
    """
    Retrieve the recorded events of a biblical person's life in chronological order.

    Returns each event with its location and date where known, plus a Mermaid
    timeline diagram. Moses returns birth, burning bush, exodus, Sinai, and death on
    Nebo; Paul returns conversion, missionary journeys, imprisonment, and Rome.

    This is the only tool covering event sequence and dating for a person. Related
    tools: `lookup_name` for identity and relationships, `explore_genealogy` for
    lineage.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "person" => %{
          "type" => "string",
          "description" => "Name of the person (e.g., 'Moses', 'Paul', 'David')"
        }
      },
      "required" => ["person"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc "An event of the timeline: `start_year` negative for BC, nil when unknown."
  @type event :: %{
          id: String.t(),
          title: String.t(),
          start_year: integer() | nil,
          duration: String.t() | nil,
          places: [Graph.entity()]
        }

  @type t :: %{person: Graph.entity(), events: [event()]}

  @doc "The timeline of `args`' person (possibly empty); an unknown person is an error."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    case Args.string(args, "person") do
      "" ->
        {:error, "Please provide a person's name."}

      name ->
        case DB.with_pack(:graph, &timeline(&1, name)) do
          {:ok, nil} ->
            {:error, "No person found matching '#{name}' in the Theographic database."}

          other ->
            other
        end
    end
  end

  defp timeline(conn, name) do
    with %{} = person <- Graph.find_person(conn, name) do
      events =
        conn
        |> DB.all(
          """
          SELECT e.* FROM graph_person_event_edges pe
          JOIN graph_events e ON e.id = pe.event_id
          WHERE pe.person_id = ?
          ORDER BY e.sort_key
          """,
          [person["id"]]
        )
        |> Enum.map(fn event ->
          places =
            conn
            |> DB.all(
              """
              SELECT p.* FROM graph_event_place_edges ep
              JOIN graph_places p ON p.id = ep.place_id
              WHERE ep.event_id = ?
              """,
              [event["id"]]
            )
            |> Enum.map(&Graph.entity/1)

          %{
            id: event["id"],
            title: event["title"],
            start_year: event["start_year"],
            duration: event["duration"],
            places: places
          }
        end)

      %{person: Graph.entity(person), events: events}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{person: person, events: []}) do
    "## Timeline of #{person.name}\n\nNo events found in the Theographic database.\n"
  end

  def render(%{person: person, events: events}) do
    lines =
      Enum.flat_map(events, fn event ->
        ["- **#{event.title}**#{Graph.year_suffix(event.start_year)}"] ++
          if event.places == [],
            do: [],
            else: ["  Location: #{Enum.map_join(event.places, ", ", & &1.name)}"]
      end)

    Enum.join(["## Timeline of #{person.name}\n" | lines] ++ [""], "\n") <>
      "\n### Timeline Diagram\n#{diagram(person.name, events)}\n"
  end

  defp diagram(name, events) do
    lines =
      Enum.flat_map(events, fn event ->
        title = String.replace(event.title, "\"", "'")
        year = Graph.year_suffix(event.start_year)

        label =
          if year == "", do: Graph.take(title, 20), else: Graph.year(event.start_year)

        ["    #{label} : #{title}"] ++
          if event.places == [],
            do: [],
            else: ["        : #{event.places |> Enum.take(3) |> Enum.map_join(", ", & &1.name)}"]
      end)

    Enum.join(["```mermaid", "timeline", "    title #{name}" | lines] ++ ["```"], "\n")
  end
end
