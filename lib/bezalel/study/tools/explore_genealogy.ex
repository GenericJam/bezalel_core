defmodule Bezalel.Study.Tools.ExploreGenealogy do
  @moduledoc """
  `explore_genealogy`: a person's ancestors and/or descendants over several
  generations, with spouses, siblings and a Mermaid family tree (the graph
  pack).

  Ported from studybible-mcp's `handle_explore_genealogy`,
  `graph_get_ancestors`, `graph_get_descendants`, `format_genealogy` and
  `mermaid_genealogy` (MIT). Same text, except: a `direction` other than
  ancestors, descendants or both is an error, and a null one is both
  (theirs traced nothing and said "No genealogical data"); a null or
  non-numeric `generations` is the default 5 (theirs traced nothing for
  null and every generation for text). An unknown person is an error.
  `result/1` returns the tree as lists of people, each linked to the person
  one generation nearer the focal person.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Graph}

  @directions ["ancestors", "descendants", "both"]
  @default_generations 5

  @impl true
  def name, do: "explore_genealogy"

  @impl true
  def description do
    """
    Trace a genealogy: a biblical person's ancestors and/or descendants across multiple generations of lineage.

    Traverses genealogical data covering 1,100+ biblical persons. Returns a family
    tree with generation numbers and relationship types, plus a Mermaid diagram of
    the tree.

    Covers questions such as tracing the line from Abraham to David, a person's
    tribal ancestry, the Messianic lineage, or how a figure connects into a known
    line. For a single generation (e.g. one person's father), `lookup_name` returns
    immediate family without the traversal.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "person" => %{
          "type" => "string",
          "description" => "Name of the person (e.g., 'David', 'Abraham', 'Jesus')"
        },
        "direction" => %{
          "type" => "string",
          "enum" => @directions,
          "description" => "Direction to trace. Default: both"
        },
        "generations" => %{
          "type" => "integer",
          "description" => "Maximum generations to trace. Default: #{@default_generations}"
        }
      },
      "required" => ["person"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc """
  A person in the tree: `generation` counts from the focal person (1 =
  parents or children), `relationship` is "father_of" or "mother_of", and
  `child_id` (ancestors) or `parent_id` (descendants) is the person one
  generation nearer whose parent or child they are. A person reached by two
  lines appears once per line.
  """
  @type node_ :: %{
          id: String.t(),
          name: String.t(),
          generation: pos_integer(),
          relationship: String.t(),
          birth_year: integer() | nil,
          death_year: integer() | nil,
          child_id: String.t() | nil,
          parent_id: String.t() | nil
        }

  @type t :: %{
          person: %{id: String.t(), name: String.t(), description: String.t() | nil},
          direction: String.t(),
          generations: integer(),
          ancestors: [node_()],
          descendants: [node_()],
          family: Graph.family()
        }

  @doc """
  The genealogy `args` ask for; no person, an unknown person or an unknown
  direction is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    name = Args.string(args, "person")
    direction = Args.optional(args, "direction") || "both"

    generations =
      case Args.integer(args, "generations", @default_generations) do
        {:ok, n} -> n
        :error -> @default_generations
      end

    cond do
      name == "" ->
        {:error, "Please provide a person's name."}

      direction not in @directions ->
        {:error, "'direction' must be one of: #{Enum.join(@directions, ", ")}."}

      true ->
        case DB.with_pack(:graph, &genealogy(&1, name, direction, generations)) do
          {:ok, nil} ->
            {:error, "No person found matching '#{name}' in the Theographic database."}

          other ->
            other
        end
    end
  end

  defp genealogy(conn, name, direction, generations) do
    with %{} = person <- Graph.find_person(conn, name) do
      id = person["id"]

      %{
        person: %{id: id, name: person["name"], description: person["description"]},
        direction: direction,
        generations: generations,
        ancestors:
          if(direction in ["ancestors", "both"], do: ancestors(conn, id, generations), else: []),
        descendants:
          if(direction in ["descendants", "both"],
            do: descendants(conn, id, generations),
            else: []
          ),
        family: Graph.family(conn, id)
      }
    end
  end

  # Both walks keep the focal person's row (generation 0) because the
  # Markdown's "is there any data" test counts it.
  defp ancestors(conn, id, generations) do
    conn
    |> DB.all(
      """
      WITH RECURSIVE ancestors AS (
          SELECT p.id, p.name, p.gender, p.birth_year, p.death_year,
                 0 as generation, 'self' as relationship,
                 NULL as child_id
          FROM graph_people p WHERE p.id = ?

          UNION ALL

          SELECT p.id, p.name, p.gender, p.birth_year, p.death_year,
                 a.generation + 1,
                 e.relationship_type,
                 e.to_person_id
          FROM ancestors a
          JOIN graph_family_edges e ON e.to_person_id = a.id
          JOIN graph_people p ON p.id = e.from_person_id
          WHERE e.relationship_type IN ('father_of', 'mother_of')
            AND a.generation < ?
      )
      SELECT * FROM ancestors ORDER BY generation
      """,
      [id, generations]
    )
    |> nodes()
  end

  defp descendants(conn, id, generations) do
    conn
    |> DB.all(
      """
      WITH RECURSIVE descendants AS (
          SELECT p.id, p.name, p.gender, p.birth_year, p.death_year,
                 0 as generation, 'self' as relationship,
                 NULL as parent_id
          FROM graph_people p WHERE p.id = ?

          UNION ALL

          SELECT p.id, p.name, p.gender, p.birth_year, p.death_year,
                 d.generation + 1,
                 e.relationship_type,
                 e.from_person_id
          FROM descendants d
          JOIN graph_family_edges e ON e.from_person_id = d.id
          JOIN graph_people p ON p.id = e.to_person_id
          WHERE e.relationship_type IN ('father_of', 'mother_of')
            AND d.generation < ?
      )
      SELECT * FROM descendants ORDER BY generation
      """,
      [id, generations]
    )
    |> nodes()
  end

  defp nodes(rows) do
    for row <- rows, row["generation"] > 0 do
      %{
        id: row["id"],
        name: row["name"],
        generation: row["generation"],
        relationship: row["relationship"],
        birth_year: row["birth_year"],
        death_year: row["death_year"],
        child_id: row["child_id"],
        parent_id: row["parent_id"]
      }
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{person: person, ancestors: ancestors, descendants: descendants, family: family}) do
    lines =
      ["## Genealogy of #{person.name}\n"] ++
        tree(ancestors, "Ancestors") ++
        tree(descendants, "Descendants") ++
        if(ancestors == [] and descendants == [],
          do: ["No genealogical data found in the Theographic database.\n"],
          else: []
        )

    family_lines =
      for {label, people} <- [{"Spouse(s)", family.partners}, {"Siblings", family.siblings}],
          people != [] do
        "**#{label}**: #{Enum.map_join(people, ", ", & &1.name)}"
      end

    Enum.join(lines, "\n") <>
      if(family_lines == [],
        do: "",
        else: "\n### Immediate Family\n" <> Enum.join(family_lines, "\n") <> "\n"
      ) <>
      if(Format.present?(person.description),
        do: "\n### About\n#{person.description}\n",
        else: ""
      ) <>
      "\n### Family Tree Diagram\n#{diagram(person.name, ancestors, descendants, family)}\n"
  end

  defp tree([], _heading), do: []

  defp tree(people, heading) do
    lines =
      for p <- people do
        indent = String.duplicate("  ", p.generation)
        relationship = p.relationship |> String.replace("_of", "") |> Format.title()
        "#{indent}- **#{p.name}** (#{relationship})#{Graph.year_suffix(p.birth_year)}"
      end

    ["### #{heading}" | lines] ++ [""]
  end

  defp diagram(name, ancestors, descendants, family) do
    focal = Graph.mermaid_id(name)

    head = [
      "```mermaid",
      "graph TD",
      ~s(    #{focal}["#{name}"]),
      "    style #{focal} fill:#4a90d9,color:#fff,stroke:#2a5a8a"
    ]

    names = Map.new(ancestors, &{&1.id, &1.name})

    ancestor_edges =
      for p <- Enum.sort_by(ancestors, &(-&1.generation)),
          edge = ancestor_edge(p, focal, names),
          do: edge

    child_edges =
      for d <- descendants, d.generation == 1 do
        did = Graph.mermaid_id(d.name)

        {{focal, did},
         [~s(    #{focal} -->|#{String.replace(d.relationship, "_of", "")}| #{did}["#{d.name}"])]}
      end

    partner_edges =
      for p <- family.partners do
        pid = Graph.mermaid_id(p.name)

        {{focal, pid},
         [
           ~s(    #{focal} -.-|spouse| #{pid}["#{p.name}"]),
           "    style #{pid} fill:#d9a04a,color:#fff"
         ]}
      end

    {lines, _seen} =
      Enum.flat_map_reduce(ancestor_edges ++ child_edges ++ partner_edges, MapSet.new(), fn
        {key, lines}, seen ->
          if MapSet.member?(seen, key),
            do: {[], seen},
            else: {lines, MapSet.put(seen, key)}
      end)

    Enum.join(head ++ lines ++ ["```"], "\n")
  end

  # An ancestor's edge to its own child: the focal person for a parent,
  # else the child named by `child_id` (none when that child isn't a row).
  defp ancestor_edge(p, focal, names) do
    pid = Graph.mermaid_id(p.name)
    relationship = String.replace(p.relationship, "_of", "")

    cond do
      p.generation == 1 ->
        {{pid, focal}, [~s(    #{pid}["#{p.name}"] -->|#{relationship}| #{focal})]}

      child = names[p.child_id] ->
        cid = Graph.mermaid_id(child)

        {{pid, cid}, [~s(    #{pid}["#{p.name}"] -->|#{relationship}| #{cid}["#{child}"])]}

      true ->
        nil
    end
  end
end
