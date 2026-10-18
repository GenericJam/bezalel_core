defmodule Bezalel.Study.Tools.GraphToolsTest do
  # explore_genealogy, explore_person_events, explore_place, find_connection
  # and graph_enriched_search, ported from studybible-mcp's
  # tests/test_tool_handlers.py against the fixture packs. The graph fixture
  # keeps every ancestor of the people the tests walk (with their spouses,
  # siblings and two generations of descendants) and all places and events,
  # so these answers are the real pack's.
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Citation, Preferences}

  alias Bezalel.Study.Tools.{
    ExploreGenealogy,
    ExplorePersonEvents,
    ExplorePlace,
    FindConnection,
    GraphEnrichedSearch
  }

  @theographic "https://theographic.netlify.app/"

  defp ok(tool, args) do
    {text, _citations} = cited(tool, args)
    text
  end

  defp cited(tool, args) do
    assert {:ok, {:details, text, %{citations: citations}}} = tool.run(args, %{})
    {text, citations}
  end

  defp person(id, name), do: "[#{name} (Theographic)](#{@theographic}person/#{id}/)"
  defp urls(citations), do: Enum.map(citations, & &1.url)

  # graph_enriched_search's verse in the BSB (the NET's: translations_test.exs).
  defp bsb(args) do
    prefs = Preferences.new(translation: "bsb")
    assert {:ok, result} = GraphEnrichedSearch.result(args, prefs)
    GraphEnrichedSearch.render(result)
  end

  defp section(text, heading) do
    [_, rest] = String.split(text, heading <> "\n", parts: 2)
    rest |> String.split("\n\n", parts: 2) |> hd()
  end

  defp parent_edges(text) do
    for [_, parent, child] <-
          Regex.scan(~r/^\s*(\w+)(?:\["[^"]*"\])? -->\|(?:father|mother)\| (\w+)/m, text),
        into: MapSet.new(),
        do: {parent, child}
  end

  describe "explore_genealogy" do
    test "ancestors default to five generations" do
      text = ok(ExploreGenealogy, %{"person" => "Hezron", "direction" => "ancestors"})
      assert text =~ ~r/\A## Genealogy of Hezron\n/
      assert text =~ "\n  - **Pharez** (Father) (1720 BC)\n"
      assert text =~ "\n        - **Isaac** (Father) (1895 BC)\n"

      for name <- ~w(Judah Tamar Israel Leah Rebekah Abraham Sarah) do
        assert text =~ "**#{name}**"
      end

      refute text =~ "Terah"
      refute text =~ "### Descendants"
      assert text =~ "```mermaid\ngraph TD"

      deeper =
        ok(ExploreGenealogy, %{
          "person" => "Hezron",
          "direction" => "ancestors",
          "generations" => 6
        })

      assert deeper =~ "**Terah** (Father)"
    end

    test "the diagram draws every parent edge in range and only those" do
      text = ok(ExploreGenealogy, %{"person" => "Hezron", "direction" => "ancestors"})

      assert parent_edges(text) ==
               MapSet.new([
                 {"Pharez", "Hezron"},
                 {"Judah", "Pharez"},
                 {"Tamar", "Pharez"},
                 {"Israel", "Judah"},
                 {"Leah", "Judah"},
                 {"Isaac", "Israel"},
                 {"Rebekah", "Israel"},
                 {"Laban", "Leah"},
                 {"Abraham", "Isaac"},
                 {"Sarah", "Isaac"},
                 {"Bethuel", "Rebekah"},
                 {"Bethuel", "Laban"}
               ])
    end

    test "result/1 links each ancestor to the person one generation down" do
      {:ok, result} =
        ExploreGenealogy.result(%{"person" => "Hezron", "direction" => "ancestors"})

      assert result.person.id == "hezron_1520"
      assert result.descendants == []
      assert Enum.max_by(result.ancestors, & &1.generation).generation == 5

      for person <- result.ancestors do
        nearer =
          if person.generation == 1,
            do: [result.person.id],
            else: for(a <- result.ancestors, a.generation == person.generation - 1, do: a.id)

        assert person.child_id in nearer
        assert person.relationship in ["father_of", "mother_of"]
      end
    end

    test "descendants, spouse and description" do
      text =
        ok(ExploreGenealogy, %{
          "person" => "Abraham",
          "direction" => "descendants",
          "generations" => 2
        })

      descendants = section(text, "### Descendants")

      for name <- ~w(Isaac Ishmael Israel Esau) do
        assert descendants =~ "**#{name}**"
      end

      refute text =~ "Judah"
      refute text =~ "### Ancestors"
      assert text =~ ~r/\*\*Spouse\(s\)\*\*: .*Sarah/
      assert text =~ "\n### About\n"
      assert text =~ "    Abraham -->|father| Isaac[\"Isaac\"]"
    end

    test "an alias finds the person" do
      assert ok(ExploreGenealogy, %{"person" => "Abram"}) =~ ~r/\A## Genealogy of Abraham\n/
    end

    test "no family, unknown people and bad arguments" do
      lone = ok(ExploreGenealogy, %{"person" => "Melchizedek"})
      assert lone =~ "No genealogical data found in the Theographic database."

      assert ExploreGenealogy.run(%{"person" => "Nobodyatall"}, %{}) ==
               {:error, "No person found matching 'Nobodyatall' in the Theographic database."}

      assert ExploreGenealogy.run(%{"person" => ""}, %{}) ==
               {:error, "Please provide a person's name."}

      assert {:error, "'direction' must be one of" <> _} =
               ExploreGenealogy.run(%{"person" => "Abraham", "direction" => "up"}, %{})
    end

    test "Source lines cite the person, each list's people and the family in Theographic" do
      {text, citations} = cited(ExploreGenealogy, %{"person" => "Aaron"})
      aaron = "#{@theographic}person/aaron_1/"
      assert text =~ "## Genealogy of Aaron\n\nSource: [Aaron (Theographic)](#{aaron})\n"
      assert [%Citation{work: "theographic", locator: "aaron_1", url: ^aaron} | _] = citations

      {text, citations} =
        cited(ExploreGenealogy, %{"person" => "Hezron", "direction" => "ancestors"})

      {:ok, result} = ExploreGenealogy.result(%{"person" => "Hezron", "direction" => "ancestors"})

      assert text =~
               ~r/### Ancestors\n(.+\n)+\nSource: #{Regex.escape(person("pharez_2338", "Pharez"))} · /

      shown =
        [result.person | result.ancestors ++ result.family.partners ++ result.family.siblings]
        |> Enum.map(&"#{@theographic}person/#{&1.id}/")
        |> Enum.uniq()

      assert urls(citations) == shown
    end
  end

  describe "explore_person_events" do
    test "events in chronological order with their places" do
      text = ok(ExplorePersonEvents, %{"person" => "Abraham"})
      assert text =~ ~r/\A## Timeline of Abraham\n/

      assert for([_, title] <- Regex.scan(~r/^- \*\*(.+?)\*\*/m, text), do: title) == [
               "Lifetime of Abraham",
               "Birth of Abraham",
               "Abraham enters Canaan",
               "Abrahamic Covenant",
               "Abraham goes to Egypt",
               "Sojourn in Canaan and Egypt",
               "Abraham and Lot Separate",
               "Birth of Ishmael",
               "Sodom Destroyed",
               "Birth of Isaac",
               "Death of Abraham"
             ]

      assert text =~ "- **Birth of Abraham** (1995 BC)\n  Location: Ur of the Chaldees\n"
      assert text =~ "```mermaid\ntimeline\n    title Abraham"
      # The diagram names at most three places an event.
      assert text =~
               "    1920 BC : Abraham enters Canaan\n        : Ai, Bethel (of Palestine), Canaan\n"
    end

    test "result/1 is the timeline" do
      {:ok, %{person: %{name: "Abraham"}, events: events}} =
        ExplorePersonEvents.result(%{"person" => "Abraham"})

      birth = Enum.find(events, &(&1.title == "Birth of Abraham"))
      assert birth.start_year == -1995
      assert [%{name: "Ur of the Chaldees"}] = birth.places
    end

    test "no events, unknown people and no name" do
      none = ok(ExplorePersonEvents, %{"person" => "Melchizedek"})
      assert none =~ "No events found in the Theographic database."
      refute none =~ "```mermaid"

      assert ExplorePersonEvents.run(%{"person" => "Nobodyatall"}, %{}) ==
               {:error, "No person found matching 'Nobodyatall' in the Theographic database."}

      assert ExplorePersonEvents.run(%{"person" => ""}, %{}) ==
               {:error, "Please provide a person's name."}
    end

    test "a Source line under the person and under each event, with its places" do
      {text, citations} = cited(ExplorePersonEvents, %{"person" => "Abraham"})
      event = "[Birth of Abraham (Theographic)](#{@theographic}event/birth_of_abraham_65/)"
      ur = "[Ur of the Chaldees (Theographic)](#{@theographic}place/ur_1189/)"

      assert text =~ "## Timeline of Abraham\n\nSource: #{person("abraham_58", "Abraham")}\n"

      assert text =~
               "- **Birth of Abraham** (1995 BC)\n  Location: Ur of the Chaldees\n" <>
                 "  Source: #{event} · #{ur}\n"

      assert hd(citations).url == "#{@theographic}person/abraham_58/"
      assert "#{@theographic}event/birth_of_abraham_65/" in urls(citations)
      assert "#{@theographic}place/ur_1189/" in urls(citations)

      assert ok(ExplorePersonEvents, %{"person" => "Melchizedek"}) ==
               "## Timeline of Melchisedec\n\n" <>
                 "Source: #{person("melchisedec_1991", "Melchisedec")}\n\n" <>
                 "No events found in the Theographic database.\n"
    end
  end

  describe "explore_place" do
    test "events, people and coordinates" do
      text = ok(ExplorePlace, %{"place" => "Hebron"})

      assert text =~
               ~r/\A## Hebron\n\n\*\*Type\*\*: City\n\*\*Coordinates\*\*: 31.5358, 35.0941\n/

      assert text =~ "### Events at this location\n- **Abraham and Lot Separate** (1919 BC)\n"
      assert text =~ "### Born here\n- Absalom\n"
      assert text =~ "```mermaid\ngraph TD"
      assert text =~ "    Absalom_b[\"Absalom\"] -->|born| Hebron"

      {:ok, result} = ExplorePlace.result(%{"place" => "Hebron"})
      assert result.place.id == "hebron_551"
      assert %{id: "absalom_59", name: "Absalom"} in result.born_here
    end

    test "nothing recorded, unknown places and no name" do
      assert ok(ExplorePlace, %{"place" => "Zoar"}) =~
               "No detailed history found in the Theographic database."

      assert ExplorePlace.run(%{"place" => "Atlantis"}, %{}) ==
               {:error, "No place found matching 'Atlantis' in the Theographic database."}

      assert ExplorePlace.run(%{"place" => ""}, %{}) == {:error, "Please provide a place name."}
    end

    test "an exact name first, namesakes by how many verses mention them" do
      {:ok, %{place: place}} = ExplorePlace.result(%{"place" => "Ai"})
      assert place.name == "Ai"
      # The Ai of Joshua 7-8, not the Ai of Jeremiah 49:3.
      assert place.id == "ai_36"
    end

    test "Source lines cite the place, its events and its people" do
      {text, citations} = cited(ExplorePlace, %{"place" => "Hebron"})
      hebron = "#{@theographic}place/hebron_551/"

      assert text =~
               "**Coordinates**: 31.5358, 35.0941\nSource: [Hebron (Theographic)](#{hebron})\n"

      assert text =~
               ~r/### Born here\n(- .+\n)+\nSource: .*#{Regex.escape(person("absalom_59", "Absalom"))}/

      assert text =~
               ~r/### Events at this location\n(- .+\n)+\nSource: \[Abraham and Lot Separate/

      assert [%Citation{work: "theographic", label: "Hebron (Theographic)", url: ^hebron} | rest] =
               citations

      assert "#{@theographic}person/absalom_59/" in urls(rest)
    end
  end

  describe "find_connection" do
    test "paths down and up the family tree" do
      text = ok(FindConnection, %{"person1" => "Esau", "person2" => "Hezron"})
      assert text =~ ~r/\A## Connection: Esau → Hezron\n/

      assert text =~
               "- Esau → *Sibling Of* → Israel\n" <>
                 "- Israel → *Father Of* → Judah\n" <>
                 "- Judah → *Father Of* → Pharez\n" <>
                 "- Pharez → *Father Of* → Hezron\n"

      assert text =~ "```mermaid\ngraph LR"

      upward = ok(FindConnection, %{"person1" => "Hezron", "person2" => "Abraham"})
      assert upward =~ "- Hezron → *Child Of* → Pharez"
      assert upward =~ "- Isaac → *Child Of* → Abraham"

      {:ok, %{steps: steps}} =
        FindConnection.result(%{"person1" => "Hezron", "person2" => "Abraham"})

      assert hd(steps).from.id == "hezron_1520"
      assert List.last(steps).to.id == "abraham_58"

      for [a, b] <- Enum.chunk_every(steps, 2, 1, :discard), do: assert(a.to == b.from)
    end

    test "no connection, unknown people and missing names" do
      unrelated = ok(FindConnection, %{"person1" => "Abraham", "person2" => "Melchizedek"})
      assert unrelated =~ "No family connection found in the Theographic database."
      refute unrelated =~ "```mermaid"

      assert ok(FindConnection, %{"person1" => "Abraham", "person2" => "Abram"}) =~
               "No family connection found"

      assert FindConnection.run(%{"person1" => "Abraham", "person2" => "Nobodyatall"}, %{}) ==
               {:error, "No person found matching 'Nobodyatall'."}

      assert FindConnection.run(%{"person1" => "Abraham"}, %{}) ==
               {:error, "Please provide both person1 and person2 names."}
    end

    test "a Source line cites everyone on the path, or the two people" do
      {text, citations} = cited(FindConnection, %{"person1" => "Esau", "person2" => "Hezron"})

      line =
        Enum.map_join(
          [
            {"esau_1216", "Esau"},
            {"israel_682", "Israel"},
            {"judah_1751", "Judah"},
            {"pharez_2338", "Pharez"},
            {"hezron_1520", "Hezron"}
          ],
          " · ",
          fn {id, name} -> person(id, name) end
        )

      assert text =~ "→ Hezron\n\nSource: #{line}\n"
      assert [_, _, _, _, _] = citations

      {text, citations} =
        cited(FindConnection, %{"person1" => "Abraham", "person2" => "Melchizedek"})

      assert text =~
               "\n\nSource: #{person("abraham_58", "Abraham")} · " <>
                 "#{person("melchisedec_1991", "Melchisedec")}\n\nNo family connection"

      assert [%{locator: "abraham_58"}, %{locator: "melchisedec_1991"}] = citations
    end
  end

  describe "graph_enriched_search" do
    test "verse text, entities and each person's family" do
      text = bsb(%{"reference" => "Exodus 31:2"})

      assert text =~
               ~r/\A## Exodus 31:2 \(BSB\)\n\n“See, I have called by name Bezalel son of Uri/

      assert text =~ "**Original**: רְאֵ֖ה"
      assert text =~ "\n**Bezaleel**\n  Parents: Uri\n"
      assert text =~ ~r/\n\*\*Hur\*\*\n  Parents: Caleb, Ephratah \| Children: .+ \(\+5 more\)\n/
      assert text =~ "### Events\n- **Tabernacle Built**\n"

      {:ok, result} = GraphEnrichedSearch.result(%{"reference" => "Exodus 31:2"})
      assert result.verse.reference == "Exo.31.2"
      bezaleel = Enum.find(result.people, &(&1.id == "bezaleel_490"))
      assert [%{name: "Uri", relationship: "father_of"}] = bezaleel.family.parents
    end

    test "abbreviations, Theographic book names and single-chapter books" do
      assert ok(GraphEnrichedSearch, %{"reference" => "Exod. 31:2"}) =~ "**Bezaleel**"
      assert ok(GraphEnrichedSearch, %{"reference" => "Jude 9"}) =~ "**Michael**"
    end

    test "never borrows another verse" do
      text = ok(GraphEnrichedSearch, %{"reference" => "John 3:1"})
      assert text =~ "**Nicodemus**"
      refute text =~ "For God so loved the world"
    end

    test "a verse stored with split numbering" do
      # Psalm 22:1 is the row 'Psa.22.1(22.2)'.
      text = bsb(%{"reference" => "Psalm 22:1"})
      assert text =~ ~r/\A## Psalm 22:1 \(BSB\)\n\nMy God, my God, why have You forsaken me\?/
    end

    test "no verse or no entities, and no reference" do
      missing = ok(GraphEnrichedSearch, %{"reference" => "Genesis 50:26"})

      assert missing ==
               "## Genesis 50:26\n\n*No entity data available for this verse in the Theographic database.*\n"

      # A verse number beyond SQLite's integer range is no verse, not a crash.
      huge = "Psalm 22:99999999999999999999"

      assert ok(GraphEnrichedSearch, %{"reference" => huge}) ==
               "## #{huge}\n\n*No entity data available for this verse in the Theographic database.*\n"

      assert GraphEnrichedSearch.run(%{"reference" => ""}, %{}) ==
               {:error, "Please provide a verse reference (e.g., 'Genesis 22:1')."}
    end

    test "Source lines cite the verse in its translation and original, each person and the lists" do
      {:ok, result} =
        GraphEnrichedSearch.result(
          %{"reference" => "Exodus 31:2"},
          Preferences.new(translation: "bsb")
        )

      text = GraphEnrichedSearch.render(result)
      citations = GraphEnrichedSearch.citations(result)
      bsb = "https://biblehub.com/exodus/31-2.htm"
      step = "https://www.stepbible.org/?q=version=THOT@reference=Exo.31.2"

      assert text =~
               ~r/\n\*\*Original\*\*: .+\n\nSource: #{Regex.escape("[Exodus 31:2](#{bsb}) · [Exodus 31:2 (Hebrew)](#{step})")}\n/

      assert text =~
               "\n**Bezaleel**\n  Parents: Uri\n  Source: #{person("bezaleel_490", "Bezaleel")} · " <>
                 "#{person("uri_2895", "Uri")}\n"

      assert text =~
               "### Events\n- **Tabernacle Built**\n\n" <>
                 "Source: [Tabernacle Built (Theographic)](#{@theographic}event/tabernacle_built_128/)\n"

      assert [%Citation{work: "bsb", url: ^bsb}, %Citation{work: "step", url: ^step} | _] =
               citations

      assert "#{@theographic}person/bezaleel_490/" in urls(citations)

      # run/2 returns the same citations, deduplicated.
      assert {:ok, {:details, _text, %{citations: [%Citation{work: verse_work} | _]}}} =
               GraphEnrichedSearch.run(%{"reference" => "Exodus 31:2"}, %{})

      assert verse_work in ["net", "bsb"]
    end
  end
end
