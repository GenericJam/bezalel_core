defmodule Bezalel.Study.Tools.ExplorePlace do
  @moduledoc """
  `explore_place`: a place's biblical history: the events recorded there,
  the people born or who died there, its coordinates, and a Mermaid network
  (the graph pack).

  Ported from studybible-mcp's `handle_explore_place`, `graph_find_place`,
  `graph_get_place_events`, `graph_get_place_people`,
  `format_place_history` and `mermaid_place_network` (MIT). Same text; an
  unknown place is an error. `result/1` returns the place with its events
  and people.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Graph}

  @impl true
  def name, do: "explore_place"

  @impl true
  def description do
    """
    Retrieve the full biblical history of a place.

    Returns the events recorded there, the people born or who died there, and
    geographic data, spanning all biblical periods — plus a Mermaid network diagram.
    Jerusalem returns events from Salem/Melchizedek through David, Solomon, the
    exile, and Jesus; Mount Sinai returns the burning bush, the giving of the law,
    the golden calf, and Elijah.

    Relevant for questions about biblical geography or a location's significance
    across salvation history. Related tool: `lookup_name` with type="place" returns
    basic place info and immediate connections only.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "place" => %{
          "type" => "string",
          "description" => "Name of the place (e.g., 'Jerusalem', 'Bethlehem', 'Egypt')"
        }
      },
      "required" => ["place"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc "An event at the place: `start_year` negative for BC, nil when unknown."
  @type event :: %{id: String.t(), title: String.t(), start_year: integer() | nil}

  @type t :: %{
          place: %{
            id: String.t(),
            name: String.t(),
            feature_type: String.t() | nil,
            latitude: float() | nil,
            longitude: float() | nil
          },
          events: [event()],
          born_here: [Graph.entity()],
          died_here: [Graph.entity()]
        }

  @doc """
  The history of the place `args` name: an exact name first, then a name
  starting with it, then one containing it, ties to the place mentioned in
  the most verses. No name or an unknown place is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    case Args.string(args, "place") do
      "" ->
        {:error, "Please provide a place name."}

      name ->
        case DB.with_pack(:graph, &history(&1, name)) do
          {:ok, nil} ->
            {:error, "No place found matching '#{name}' in the Theographic database."}

          other ->
            other
        end
    end
  end

  defp history(conn, name) do
    place =
      DB.one(
        conn,
        """
        SELECT p.* FROM graph_places p
        WHERE LOWER(p.name) LIKE LOWER(?)
        ORDER BY
            CASE
                WHEN LOWER(p.name) = LOWER(?) THEN 0
                WHEN LOWER(p.name) LIKE LOWER(?) THEN 1
                ELSE 2
            END,
            (SELECT COUNT(*) FROM graph_verse_mentions vm
             WHERE vm.entity_type = 'place' AND vm.entity_id = p.id) DESC
        LIMIT 10
        """,
        ["%#{name}%", name, "#{name}%"]
      )

    if place do
      id = place["id"]

      events =
        for row <-
              DB.all(
                conn,
                """
                SELECT e.* FROM graph_event_place_edges ep
                JOIN graph_events e ON e.id = ep.event_id
                WHERE ep.place_id = ?
                ORDER BY e.sort_key
                """,
                [id]
              ),
            do: %{id: row["id"], title: row["title"], start_year: row["start_year"]}

      people = fn column ->
        conn
        |> DB.all("SELECT * FROM graph_people WHERE #{column} = ?", [id])
        |> Enum.map(&Graph.entity/1)
      end

      %{
        place: %{
          id: id,
          name: place["name"],
          feature_type: place["feature_type"],
          latitude: place["latitude"],
          longitude: place["longitude"]
        },
        events: events,
        born_here: people.("birth_place_id"),
        died_here: people.("death_place_id")
      }
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{place: place, events: events, born_here: born, died_here: died} = result) do
    lines =
      place_lines(place) ++
        section(
          "Events at this location",
          Enum.map(events, &"- **#{&1.title}**#{Graph.year_suffix(&1.start_year)}")
        ) ++
        section("Born here", Enum.map(born, &"- #{&1.name}")) ++
        section("Died here", Enum.map(died, &"- #{&1.name}")) ++
        if(events == [] and born == [] and died == [],
          do: ["No detailed history found in the Theographic database.\n"],
          else: []
        )

    text = Enum.join(lines, "\n")

    if events == [] and born == [] and died == [],
      do: text,
      else: text <> "\n### Place Network Diagram\n#{diagram(result)}\n"
  end

  defp place_lines(place) do
    ["## #{place.name}\n"] ++
      if(Format.present?(place.feature_type), do: ["**Type**: #{place.feature_type}"], else: []) ++
      if(present_number?(place.latitude) and present_number?(place.longitude),
        do: ["**Coordinates**: #{decimals(place.latitude)}, #{decimals(place.longitude)}"],
        else: []
      ) ++ [""]
  end

  defp present_number?(value), do: is_number(value) and value != 0

  defp decimals(value), do: :erlang.float_to_binary(value * 1.0, decimals: 4)

  defp section(_heading, []), do: []
  defp section(heading, lines), do: ["### #{heading}" | lines] ++ [""]

  defp diagram(%{place: place, events: events, born_here: born, died_here: died}) do
    pid = Graph.mermaid_id(place.name)

    event_lines =
      for event <- Enum.take(events, 12) do
        eid = event.title |> Graph.take(30) |> Graph.mermaid_id()
        label = Graph.take(event.title, 40) <> Graph.year_suffix(event.start_year)
        ~s(    #{pid} --- #{eid}["#{label}"])
      end

    born_lines =
      for person <- Enum.take(born, 8) do
        id = Graph.mermaid_id(person.name) <> "_b"

        [
          ~s(    #{id}["#{person.name}"] -->|born| #{pid}),
          "    style #{id} fill:#4a90d9,color:#fff"
        ]
      end

    died_lines =
      for person <- Enum.take(died, 8) do
        id = Graph.mermaid_id(person.name) <> "_d"

        [
          ~s(    #{pid} -->|died| #{id}["#{person.name}"]),
          "    style #{id} fill:#d94a4a,color:#fff"
        ]
      end

    Enum.join(
      [
        "```mermaid",
        "graph TD",
        ~s(    #{pid}["#{place.name}"]),
        "    style #{pid} fill:#2a8a4a,color:#fff,stroke:#1a5a2a"
      ] ++ event_lines ++ List.flatten(born_lines ++ died_lines) ++ ["```"],
      "\n"
    )
  end
end
