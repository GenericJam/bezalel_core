defmodule Bezalel.Study.Tools.LookupName do
  @moduledoc """
  `lookup_name`: a biblical person, place or thing by name (TIPNR), with
  ACAI's annotations for that same entry.

  Ported from studybible-mcp's `handle_lookup_name`, `lookup_name`,
  `get_acai_entities_for_names` and `format_name_entry` (MIT). Same text,
  except that a relationship listing several names prints them as
  "Cain, Abel, Seth" where Python printed the list's repr
  ("['Cain', 'Abel', 'Seth']"). `result/1` returns each name row with its
  ACAI entity.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format}

  @default_limit 4
  @max_limit 20

  @impl true
  def name, do: "lookup_name"

  @impl true
  def description do
    """
    Look up general information about a biblical person, place, or thing by name — Abraham, David, Bethlehem, and so on.

    Covers 4,000+ biblical persons and 1,000+ places. Returns the entry's original-language
    name, description, key verse references, ACAI annotations where available (variant
    names, roles, reference and speech counts), and its immediate relationships:

    - **Parents** — one generation back (e.g. David → Jesse)
    - **Children** — one generation forward (e.g. Abraham → Isaac)
    - **Siblings** (e.g. Moses ↔ Aaron ↔ Miriam)
    - **Spouse** (e.g. Ruth ↔ Boaz)

    Relevant for identifying a named figure or location and for the immediate
    family and reference context around it. Multi-generation lineages are covered by
    `explore_genealogy`, a person's life events by `explore_person_events`, and a
    location's full history by `explore_place`.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "Name to look up (e.g., 'David', 'Jerusalem', 'Abraham')"
        },
        "type" => %{
          "type" => "string",
          "enum" => ["person", "place", "thing"],
          "description" => "Filter by type. Omit to search all types."
        },
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => @max_limit,
          "default" => @default_limit,
          "description" =>
            "Maximum entries; exact name matches come first. Default: #{@default_limit}"
        }
      },
      "required" => ["name"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc """
  The names matching `name` (exact, then prefix, then substring matches),
  each with its ACAI entity or nil, and `total`, the count before `limit`.
  """
  @type t :: %{
          name: String.t(),
          total: non_neg_integer(),
          entries: [%{entry: DB.row(), acai: DB.row() | nil}]
        }

  @doc "The names matching `args` (possibly none)."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    name = Args.string(args, "name")
    type = Args.optional(args, "type")

    case {name, Args.integer(args, "limit", @default_limit)} do
      {"", _} ->
        {:error, "Please provide a name to look up."}

      {_, {:ok, limit}} when limit in 1..@max_limit//1 ->
        DB.with_pack(:core, &lookup(&1, name, type, limit))

      _ ->
        {:error, "'limit' must be an integer from 1 to #{@max_limit}."}
    end
  end

  defp lookup(conn, name, type, limit) do
    {type_filter, type_params} = if type, do: {" AND type = ?", [type]}, else: {"", []}

    entries =
      DB.all(
        conn,
        """
        SELECT *, COUNT(*) OVER () AS match_count FROM names
        WHERE name LIKE ?#{type_filter}
        ORDER BY CASE WHEN name = ? COLLATE NOCASE THEN 0
                      WHEN name LIKE ? THEN 1 ELSE 2 END, id
        LIMIT ?
        """,
        ["%#{name}%"] ++ type_params ++ [name, "#{name}%", limit]
      )

    acai = acai_entities(conn, entries)

    %{
      name: name,
      total: if(entries == [], do: 0, else: hd(entries)["match_count"]),
      entries: Enum.map(entries, &%{entry: Map.delete(&1, "match_count"), acai: acai[&1["id"]]})
    }
  end

  # Each entry's ACAI entity by entry id. A names entry is a TIPNR entry,
  # identified by its name and first reference ('Ezra@Ezr.7.1'), and ACAI
  # lists the TIPNR entries each entity is (tipnr_keys), so namesakes get
  # their own entity. Where a place and its people share an entry (Edom,
  # the Edomites) the entry's own type wins, then the entity named like
  # the entry, then the most referenced.
  defp acai_entities(conn, entries) do
    keys =
      Map.new(entries, fn entry ->
        key =
          case Format.json(entry["refs"], []) do
            [first | _] -> "#{entry["name"]}@#{first}"
            _ -> nil
          end

        {entry["id"], key}
      end)

    wanted = keys |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    rows =
      if wanted == [],
        do: [],
        else:
          DB.all(
            conn,
            """
            SELECT k.value AS tipnr_key, a.*
            FROM acai_entities a, json_each(a.tipnr_keys) k
            WHERE k.value IN (#{DB.placeholders(wanted)})
            """,
            wanted
          )

    Map.new(entries, fn entry ->
      own_id = String.downcase("#{entry["type"]}:#{String.replace(entry["name"], " ", "")}")

      best =
        rows
        |> Enum.filter(&(&1["tipnr_key"] == keys[entry["id"]]))
        |> Enum.max_by(
          &{&1["entity_type"] == entry["type"], String.downcase(&1["id"]) == own_id,
           &1["reference_count"] || 0},
          fn -> nil end
        )

      {entry["id"], best && Map.delete(best, "tipnr_key")}
    end)
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{name: name, entries: []}), do: "No entries found for '#{name}'."

  def render(%{name: name, total: total, entries: entries}) do
    shown = length(entries)

    note =
      if total > shown,
        do:
          "*Showing #{shown} of #{total} matching names; set type or raise " <>
            "limit (at most #{@max_limit}) to see more.*\n\n",
        else: ""

    "## Biblical Names: #{name}\n\n" <>
      note <> Enum.map_join(entries, &(entry(&1.entry, &1.acai) <> "\n---\n\n"))
  end

  defp entry(entry, acai) do
    Enum.join(
      ["### #{entry["name"]}"] ++
        if(Format.present?(entry["name_original"]),
          do: ["**Original**: #{entry["name_original"]}"],
          else: []
        ) ++
        ["**Type**: #{Format.title(entry["type"] || "unknown")}", ""] ++
        if(Format.present?(entry["description"]), do: [entry["description"], ""], else: []) ++
        acai_lines(entry, acai) ++ relationships(entry) ++ key_references(entry),
      "\n"
    )
  end

  defp acai_lines(_entry, nil), do: []

  defp acai_lines(entry, acai) do
    own = String.downcase(entry["name"])

    variants =
      acai["referred_to_as"]
      |> Format.json([])
      |> Enum.map(&Format.s/1)
      |> Enum.reject(&(String.downcase(&1) == own))

    roles = Format.json(acai["roles"], [])

    parts =
      Enum.reject(
        [
          Format.present?(acai["description"]) && "**Description**: #{acai["description"]}",
          variants != [] && "**Also known as**: #{variants |> Enum.take(5) |> Enum.join(", ")}",
          Format.present?(roles) && "**Roles**: #{Enum.map_join(roles, ", ", &Format.s/1)}",
          Format.present?(acai["reference_count"]) &&
            "**Referenced in**: #{acai["reference_count"]} verses",
          Format.present?(acai["speeches_count"]) &&
            "**Attributed speeches**: #{acai["speeches_count"]}"
        ],
        &(&1 == false)
      )

    if parts == [], do: [], else: ["**ACAI Annotations**:" | parts] ++ [""]
  end

  defp relationships(entry) do
    case Format.json(entry["relationships"]) do
      [_ | _] = pairs ->
        lines =
          for {key, value} <- pairs, Format.present?(value) do
            "- #{Format.title(key)}: #{names(value)}"
          end

        ["**Relationships**:" | lines] ++ [""]

      _ ->
        []
    end
  end

  defp names(value) when is_list(value), do: Enum.map_join(value, ", ", &Format.s/1)
  defp names(value), do: Format.s(value)

  defp key_references(entry) do
    case Format.json(entry["refs"]) do
      [_ | _] = refs ->
        {shown, rest} = Enum.split(refs, 10)
        more = if rest == [], do: [], else: ["(and #{length(rest)} more)"]
        ["**Key References**: " <> Enum.join(shown, ", ")] ++ more ++ [""]

      _ ->
        []
    end
  end
end
