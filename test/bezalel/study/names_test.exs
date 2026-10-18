defmodule Bezalel.Study.Tools.NamesTest do
  # lookup_name and people_in_passage, ported from studybible-mcp's
  # tests/test_tool_handlers.py against the fixture packs. The fixture keeps
  # every name containing the tests' names, so match counts and order are
  # the real pack's.
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Citation, Preferences}
  alias Bezalel.Study.Tools.{LookupName, PeopleInPassage}

  defp ok(tool, args) do
    {text, _citations} = cited(tool, args)
    text
  end

  defp cited(tool, args) do
    assert {:ok, {:details, text, %{citations: citations}}} = tool.run(args, %{})
    {text, citations}
  end

  @step_data "https://github.com/STEPBible/STEPBible-Data"
  @acai "https://github.com/BibleAquifer/ACAI/blob/7e6a2d66/"
  @theographic "https://theographic.netlify.app/"

  defp entries(text), do: text |> String.split("\n---\n") |> Enum.drop(-1)
  defp name_hits(text), do: for([_, n] <- Regex.scan(~r/^### (.+)$/m, text), do: n)

  describe "lookup_name" do
    test "Bezalel: both namesakes, each with its own ACAI entity" do
      text = ok(LookupName, %{"name" => "Bezalel"})
      assert text =~ ~r/\A## Biblical Names: Bezalel\n\n### Bezalel\n\*\*Type\*\*: Person\n/
      [craftsman, later] = entries(text)

      assert craftsman =~ "first mentioned at Exo.31.2"
      assert craftsman =~ "**Roles**: Carpenter, Craftsman\n**Referenced in**: 8 verses\n"
      assert craftsman =~ "**Relationships**:\n- Parents: Uri\n"
      assert craftsman =~ "**Key References**: Exo.31.2"

      assert later =~ "only mentioned at Ezr.10.30"
      assert later =~ "**Also known as**: Bezaleel\n**Referenced in**: 1 verses\n"
      refute later =~ "Craftsman"
    end

    test "each entry's Source line cites its TIPNR entry and ACAI entity" do
      {text, citations} = cited(LookupName, %{"name" => "Bezalel"})
      [craftsman, later] = entries(text)

      assert craftsman =~
               "\nSource: [STEPBible proper names (Bezalel)](#{@step_data}) · " <>
                 "[Bezalel (ACAI)](#{@acai}people/md/Bezalel.md)\n"

      assert later =~ "[Bezalel (Ezra 10:30) (ACAI)](#{@acai}people/md/Bezalel.2.md)"

      # The two entries share STEPBible's dataset: one citation for both.
      assert [
               %Citation{work: "step", url: @step_data},
               %Citation{work: "acai", locator: "person:Bezalel", url: craftsman_url},
               %Citation{work: "acai", locator: "person:Bezalel.2"}
             ] = citations

      assert craftsman_url == @acai <> "people/md/Bezalel.md"
    end

    test "a place's ACAI entity is under places" do
      {text, citations} = cited(LookupName, %{"name" => "Ai", "type" => "place", "limit" => 2})
      ephraim = @acai <> "places/md/Ai.md"
      ammon = @acai <> "places/md/Ai.2.md"
      assert text =~ "[Ai (of Ephraim) (ACAI)](#{ephraim})"
      assert text =~ "[Ai (of Ammon) (ACAI)](#{ammon})"

      assert [
               %Citation{work: "step"},
               %Citation{work: "acai", locator: "place:Ai", url: ^ephraim},
               %Citation{work: "acai", locator: "place:Ai.2", url: ^ammon}
             ] = citations
    end

    test "ACAI matches each entry by its own TIPNR entry, the entry's type first" do
      text = ok(LookupName, %{"name" => "Judah", "limit" => 10})
      patriarch = Enum.find(entries(text), &(&1 =~ "**Key References**: Gen.29.35"))
      # ACAI has both the patriarch (person, 764 verses) and the tribe (group,
      # 728) for Judah@Gen.29.35; the person entry gets the person.
      assert patriarch =~ "**Roles**: Leader, Patriarch\n**Referenced in**: 764 verses"
      refute patriarch =~ "728"

      levite = Enum.find(entries(text), &(&1 =~ "**Key References**: Neh.12.8"))
      assert levite =~ "**Referenced in**: 2 verses"
      refute levite =~ "Patriarch"
    end

    test "exact matches first, then prefix, then substring; the default cap is the user's limit" do
      assert {:ok, result} = LookupName.result(%{"name" => "ai"}, Preferences.new(limit: 4))
      text = LookupName.render(result)
      assert name_hits(text) == ["Ai", "Ai", "Aiah", "Aiah"]

      assert text =~
               "*Showing 4 of 327 matching names; set type or raise limit (at most 20) to see more.*"

      # 8 by default; a setting above the tool's maximum is held to it.
      assert Enum.count(name_hits(ok(LookupName, %{"name" => "ai"}))) == 8
      assert {:ok, many} = LookupName.result(%{"name" => "ai"}, Preferences.new(limit: 50))
      assert Enum.count(many.entries) == 20
    end

    test "limit and type" do
      assert name_hits(ok(LookupName, %{"name" => "ai", "limit" => 8})) ==
               ["Ai", "Ai", "Aiah", "Aiah", "Aijalon", "Ain", "Ain", "Abigail"]

      places = ok(LookupName, %{"name" => "ai", "type" => "place", "limit" => 20})
      assert places |> String.split("**Type**: Place") |> Enum.count() == 21
      refute places =~ "**Type**: Person"
      [_, total] = Regex.run(~r/\*Showing 20 of (\d+) matching names/, places)
      assert String.to_integer(total) < 327

      assert ok(LookupName, %{"name" => "Bezalel", "type" => "place"}) ==
               "No entries found for 'Bezalel'."
    end

    for limit <- [0, 21, "many"] do
      test "limit #{inspect(limit)} is rejected" do
        assert LookupName.run(%{"name" => "Ai", "limit" => unquote(limit)}, %{}) ==
                 {:error, "'limit' must be an integer from 1 to 20."}
      end
    end

    test "no match and no name" do
      assert ok(LookupName, %{"name" => "Zzyzx"}) == "No entries found for 'Zzyzx'."
      assert LookupName.run(%{"name" => ""}, %{}) == {:error, "Please provide a name to look up."}
    end
  end

  describe "people_in_passage" do
    defp section(text, heading) do
      [_, rest] = String.split(text, heading <> "\n", parts: 2)
      rest |> String.split("\n\n", parts: 2) |> hd()
    end

    test "a chapter and a verse of Exodus 31" do
      chapter = ok(PeopleInPassage, %{"reference" => "Exodus 31"})
      assert chapter =~ ~r/\A## Entities in Exodus 31\n/
      people = section(chapter, "### People")

      for name <- ~w(Bezaleel Aholiab Moses Uri Hur) do
        assert people =~ "- **#{name}**"
      end

      assert section(chapter, "### Places") =~ "- **Mount Sinai**"
      assert section(chapter, "### Events") =~ "- **Tabernacle Built**"

      verse = ok(PeopleInPassage, %{"reference" => "Exodus 31:2"})
      assert verse =~ "- **Bezaleel**" and verse =~ "- **Uri**" and verse =~ "- **Hur**"
      refute verse =~ "Aholiab"
    end

    test "book codes map to Theographic's names" do
      # Theographic writes John as 'John.3.1', the packs 'Jhn'.
      assert ok(PeopleInPassage, %{"reference" => "John 3:1"}) =~ "- **Nicodemus**"
      assert ok(PeopleInPassage, %{"reference" => "Jn 3"}) =~ "- **Nicodemus**"
      assert ok(PeopleInPassage, %{"reference" => "Jude 9"}) =~ "- **Michael**"
    end

    test "nothing recorded, and references it can't read" do
      # The fixture has no mentions for Genesis 50.
      assert ok(PeopleInPassage, %{"reference" => "Genesis 50"}) =~
               "No entities found for this passage in the Theographic database."

      assert PeopleInPassage.run(%{"reference" => "Genesis"}, %{}) ==
               {:error,
                "Could not parse reference: Genesis. Use 'Romans 8' or 'Genesis 22:1' format."}

      assert {:error, "Please provide a Bible reference" <> _} =
               PeopleInPassage.run(%{"reference" => ""}, %{})
    end

    test "result/1 gives the entities with their graph ids" do
      {:ok, result} = PeopleInPassage.result(%{"reference" => "Exodus 31:2"})
      assert %{id: "bezaleel_490", name: "Bezaleel"} in result.people
    end

    test "a Source line under each list cites every entity in Theographic" do
      {text, citations} = cited(PeopleInPassage, %{"reference" => "Exodus 31"})
      aaron = "[Aaron (Theographic)](#{@theographic}person/aaron_1/)"

      assert text =~ ~r/### People\n(- .+\n)+\nSource: .*#{Regex.escape(aaron)}/

      assert text =~
               "### Places\n- **Holy Place**\n- **Mount Sinai**\n\n" <>
                 "Source: [Holy Place (Theographic)](#{@theographic}place/holy_place_574/) · " <>
                 "[Mount Sinai (Theographic)](#{@theographic}place/mount_sinai_855/)\n"

      assert text =~
               "- **Tabernacle Built**\n\n" <>
                 "Source: [Tabernacle Built (Theographic)](#{@theographic}event/tabernacle_built_128/)\n"

      assert %Citation{work: "theographic", label: "Aaron (Theographic)", locator: "aaron_1"} =
               Enum.find(citations, &(&1.url == "#{@theographic}person/aaron_1/"))

      {:ok, result} = PeopleInPassage.result(%{"reference" => "Exodus 31"})
      shown = length(result.people) + length(result.places) + length(result.events)
      assert length(citations) == shown
    end
  end
end
