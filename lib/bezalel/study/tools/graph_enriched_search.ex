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
  reference that isn't a verse). The verse is in the user's translation.
  A `Source:` line follows the verse (its translation and original), each
  person (Theographic, with the family shown) and each list of places or
  events. `result/1` returns the verse and the entities, each person with
  their family.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{
    Args,
    Citation,
    Citations,
    DB,
    Format,
    Graph,
    Preferences,
    Reference,
    Translations,
    Verses
  }

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
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)),
         do: Citations.details(render(result), result, citations(result))
  end

  @doc """
  The citations of everything a `result/1` shows, in order: the verse (in
  its translation, and its original on STEP), each person with the family
  shown (Theographic), the places and the events.
  """
  @spec citations(t()) :: [Citation.t()]
  def citations(result) do
    verse_sources(result.verse, result.translation) ++
      Enum.flat_map(result.people, &person_sources/1) ++
      place_sources(result.places) ++ event_sources(result.events)
  end

  defp verse_sources(nil, _translation), do: []

  defp verse_sources(view, translation) do
    verse = {view.book, view.chapter, view.verse}
    original = if view.original != "", do: [Citations.step(verse)], else: []

    if view.translated,
      do: [Citations.scripture(verse, translation) | original],
      else: [Citations.step(verse)]
  end

  defp person_sources(%{id: id, name: name, family: family}) do
    shown =
      case family_shown(family) do
        nil -> []
        f -> f.parents ++ f.partners ++ f.children
      end

    [%{id: id, name: name} | shown]
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(&Citations.person(&1.id, &1.name))
  end

  defp place_sources(places), do: Enum.map(places, &Citations.place(&1.id, &1.name))
  defp event_sources(events), do: Enum.map(events, &Citations.event(&1.id, &1.name))

  # The family a person's entry shows: parents, spouses and the first five
  # children (`more`: how many children it leaves out).
  defp family_shown(nil), do: nil

  defp family_shown(family) do
    {children, rest} = Enum.split(family.children, 5)
    %{parents: family.parents, partners: family.partners, children: children, more: length(rest)}
  end

  @typedoc "A person mentioned, with the family of the person their name finds (nil if none)."
  @type person :: %{id: String.t(), name: String.t(), family: Graph.family() | nil}

  @typedoc """
  The verse in `translation` (`translation_note`: why it isn't the one
  chosen, or nil) and its entities.
  """
  @type t :: %{
          reference: String.t(),
          verse: Format.verse_view() | nil,
          people: [person()],
          places: [Graph.entity()],
          events: [Graph.entity()],
          translation: Translations.ref(),
          translation_note: String.t() | nil
        }

  @doc "The verse and entities of `args`' reference, under the host's current preferences."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args), do: result(args, Preferences.current())

  @doc "The verse (in `prefs`' translation) and entities of `args`' reference (either possibly missing)."
  @spec result(map(), Preferences.t()) :: {:ok, t()} | {:error, String.t()}
  def result(args, prefs) do
    case Args.reference(args) do
      "" ->
        {:error, "Please provide a verse reference (e.g., 'Genesis 22:1')."}

      reference ->
        with {:ok, entities} <- DB.with_pack(:graph, &entities(&1, reference)) do
          Translations.with_translation(prefs.translation, &verse(entities, reference, &1, &2))
        end
    end
  end

  defp verse(entities, reference, translation, note) do
    with {:ok, row} <- DB.with_pack(:core, &Verses.get(&1, reference, translation)) do
      {:ok,
       Map.merge(entities, %{
         reference: reference,
         verse: row && Format.verse_view(row),
         translation: Translations.ref(translation),
         translation_note: note
       })}
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
        events: events,
        translation: translation,
        translation_note: note
      }) do
    verse_lines = verse_lines(verse, note, translation)

    people_lines =
      if people == [],
        do: [],
        else: ["### People Mentioned" | Enum.flat_map(people, &person_lines/1)] ++ [""]

    lines =
      ["## #{reference}#{Format.translation_label(List.wrap(verse), translation)}\n"] ++
        verse_lines ++
        people_lines ++
        list("Places Mentioned", places, place_sources(places)) ++
        list("Events", events, event_sources(events)) ++
        if(people == [] and places == [] and events == [],
          do: ["*No entity data available for this verse in the Theographic database.*\n"],
          else: []
        )

    Enum.join(lines, "\n")
  end

  # The verse's English (after the translation note, if any) and original.
  defp verse_lines(nil, _note, _translation), do: []

  defp verse_lines(view, note, translation) do
    if(note, do: ["*#{note}*\n"], else: []) ++
      [view.english, ""] ++
      if(view.original != "", do: ["**Original**: #{view.original}", ""], else: []) ++
      [Citation.source_line(verse_sources(view, translation)), ""]
  end

  defp person_lines(%{name: name, family: family} = person) do
    parts =
      case family_shown(family) do
        nil ->
          []

        shown ->
          more = if shown.more == 0, do: "", else: " (+#{shown.more} more)"

          Enum.reject(
            [
              shown.parents != [] && "Parents: #{names(shown.parents)}",
              shown.partners != [] && "Spouse: #{names(shown.partners)}",
              shown.children != [] && "Children: #{names(shown.children)}#{more}"
            ],
            &(&1 == false)
          )
      end

    ["\n**#{name}**"] ++
      if(parts == [], do: [], else: ["  " <> Enum.join(parts, " | ")]) ++
      ["  " <> Citation.source_line(person_sources(person))]
  end

  defp names(people), do: Enum.map_join(people, ", ", & &1.name)

  defp list(_heading, [], _citations), do: []

  defp list(heading, entities, citations),
    do:
      ["### #{heading}" | Enum.map(entities, &"- **#{&1.name}**")] ++
        ["", Citation.source_line(citations), ""]
end
