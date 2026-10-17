defmodule Bezalel.Study.Tools.FindConnection do
  @moduledoc """
  `find_connection`: the shortest family path between two people over
  parent, child, sibling and spouse edges, with a Mermaid flowchart (the
  graph pack).

  Ported from studybible-mcp's `handle_find_connection`, `graph_find_path`
  (a breadth-first search over every family edge, at most 15 steps),
  `format_connection_path` and `mermaid_connection_path` (MIT). Same text;
  an unknown person is an error. `result/1` returns the path as a list of
  steps.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Graph}

  @max_depth 15

  @impl true
  def name, do: "find_connection"

  @impl true
  def description do
    """
    Trace the shortest family relationship path between two biblical people.

    Walks parent, child, sibling, and spouse relationships in the biblical
    genealogies to find a connecting path, and returns it as a Mermaid flowchart.
    Ruth and David return Ruth → Obed → Jesse → David; Abraham and Moses trace
    through Levi. Where no family connection exists, that is reported.

    Relevant for questions about how two named figures relate. Related tool:
    `explore_genealogy` returns one person's ancestors or descendants rather than a
    path between two people.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "person1" => %{
          "type" => "string",
          "description" => "First person's name (e.g., 'Abraham')"
        },
        "person2" => %{
          "type" => "string",
          "description" => "Second person's name (e.g., 'David')"
        }
      },
      "required" => ["person1", "person2"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc """
  A step of the path: `relationship` is the edge from `from` to `to`
  ("father_of", "mother_of", "sibling_of", "partner_of", or "child_of"
  walking a parent edge upward).
  """
  @type step :: %{from: Graph.entity(), relationship: String.t(), to: Graph.entity()}

  @type t :: %{from: Graph.entity(), to: Graph.entity(), steps: [step()]}

  @doc """
  The path between `args`' two people, empty when they aren't connected
  (or are the same person); a missing or unknown name is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    name1 = Args.string(args, "person1")
    name2 = Args.string(args, "person2")

    if name1 == "" or name2 == "" do
      {:error, "Please provide both person1 and person2 names."}
    else
      case DB.with_pack(:graph, &connection(&1, name1, name2)) do
        {:ok, {:unknown, name}} -> {:error, "No person found matching '#{name}'."}
        other -> other
      end
    end
  end

  defp connection(conn, name1, name2) do
    person1 = Graph.find_person(conn, name1)
    person2 = Graph.find_person(conn, name2)

    cond do
      person1 == nil ->
        {:unknown, name1}

      person2 == nil ->
        {:unknown, name2}

      true ->
        %{
          from: Graph.entity(person1),
          to: Graph.entity(person2),
          steps: path(conn, person1["id"], person2["id"])
        }
    end
  end

  defp path(_conn, id, id), do: []

  defp path(conn, from, to) do
    adjacency = adjacency(conn)

    case search(:queue.from_list([{from, [from]}]), MapSet.new([from]), to, adjacency) do
      nil -> []
      ids -> steps(conn, ids, adjacency)
    end
  end

  # Each person's neighbours in edge order, a parent edge also walked
  # upward as child_of.
  defp adjacency(conn) do
    conn
    |> DB.all("SELECT from_person_id, to_person_id, relationship_type FROM graph_family_edges")
    |> Enum.reduce(%{}, fn %{
                             "from_person_id" => a,
                             "to_person_id" => b,
                             "relationship_type" => rel
                           },
                           acc ->
      reverse =
        case rel do
          parent when parent in ["father_of", "mother_of"] -> "child_of"
          "child_of" -> "parent_of"
          other -> other
        end

      acc
      |> Map.update(a, [{b, rel}], &[{b, rel} | &1])
      |> Map.update(b, [{a, reverse}], &[{a, reverse} | &1])
    end)
    |> Map.new(fn {id, neighbours} -> {id, Enum.reverse(neighbours)} end)
  end

  # Breadth-first; a path is the ids from the start, newest first.
  defp search(queue, visited, to, adjacency) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

      {{:value, {_current, path}}, rest} when length(path) - 1 >= @max_depth ->
        search(rest, visited, to, adjacency)

      {{:value, {current, path}}, rest} ->
        result =
          adjacency
          |> Map.get(current, [])
          |> Enum.reduce_while({rest, visited}, &visit(&1, &2, path, to))

        case result do
          {:found, ids} -> ids
          {queue, visited} -> search(queue, visited, to, adjacency)
        end
    end
  end

  defp visit({neighbour, _rel}, {queue, visited}, path, to) do
    cond do
      MapSet.member?(visited, neighbour) ->
        {:cont, {queue, visited}}

      neighbour == to ->
        {:halt, {:found, Enum.reverse([neighbour | path])}}

      true ->
        {:cont,
         {:queue.in({neighbour, [neighbour | path]}, queue), MapSet.put(visited, neighbour)}}
    end
  end

  defp steps(conn, ids, adjacency) do
    unique = Enum.uniq(ids)

    names =
      conn
      |> DB.all(
        "SELECT id, name FROM graph_people WHERE id IN (#{DB.placeholders(unique)})",
        unique
      )
      |> Map.new(&{&1["id"], &1["name"]})

    ids
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      relationship =
        Enum.find_value(Map.get(adjacency, a, []), "related_to", fn {id, rel} ->
          id == b && rel
        end)

      %{
        from: %{id: a, name: Map.get(names, a, a)},
        relationship: relationship,
        to: %{id: b, name: Map.get(names, b, b)}
      }
    end)
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{from: from, to: to, steps: []}) do
    "## Connection: #{from.name} → #{to.name}\n\nNo family connection found in the Theographic database.\n"
  end

  def render(%{from: from, to: to, steps: steps}) do
    lines =
      for step <- steps do
        relationship = step.relationship |> String.replace("_", " ") |> Format.title()
        "- #{step.from.name} → *#{relationship}* → #{step.to.name}"
      end

    Enum.join(["## Connection: #{from.name} → #{to.name}\n" | lines] ++ [""], "\n") <>
      "\n### Relationship Diagram\n#{diagram(from.name, to.name, steps)}\n"
  end

  defp diagram(name1, name2, steps) do
    {edges, _seen} =
      Enum.flat_map_reduce(steps, MapSet.new(), fn step, seen ->
        fid = Graph.mermaid_id(step.from.name)
        tid = Graph.mermaid_id(step.to.name)

        if MapSet.member?(seen, {fid, tid}) do
          {[], seen}
        else
          relationship = String.replace(step.relationship, "_", " ")

          {[~s(    #{fid}["#{step.from.name}"] -->|#{relationship}| #{tid}["#{step.to.name}"])],
           MapSet.put(seen, {fid, tid})}
        end
      end)

    Enum.join(
      [
        "```mermaid",
        "graph LR",
        "    style #{Graph.mermaid_id(name1)} fill:#4a90d9,color:#fff,stroke:#2a5a8a",
        "    style #{Graph.mermaid_id(name2)} fill:#d94a4a,color:#fff,stroke:#8a2a2a"
      ] ++ edges ++ ["```"],
      "\n"
    )
  end
end
