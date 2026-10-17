defmodule Bezalel.Study.Tools.NamesTest do
  # lookup_name and people_in_passage, ported from studybible-mcp's
  # tests/test_tool_handlers.py against the fixture packs. The fixture keeps
  # every name containing the tests' names, so match counts and order are
  # the real pack's.
  use ExUnit.Case, async: true

  alias Bezalel.Study.Tools.{LookupName, PeopleInPassage}

  defp ok(tool, args) do
    assert {:ok, text} = tool.run(args, %{})
    text
  end

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

    test "exact matches first, then prefix, then substring; the default cap is four" do
      text = ok(LookupName, %{"name" => "ai"})
      assert name_hits(text) == ["Ai", "Ai", "Aiah", "Aiah"]

      assert text =~
               "*Showing 4 of 327 matching names; set type or raise limit (at most 20) to see more.*"
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
  end
end
