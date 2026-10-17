defmodule Bezalel.Study.Tools.NotesToolsTest do
  # get_study_notes, get_bible_dictionary, get_key_terms, get_ane_context,
  # get_theology_context and list_research_sources, ported from
  # studybible-mcp's tests/test_tool_handlers.py, test_theology_context.py,
  # test_broad_entry_refinement.py and test_research_sources.py against the
  # fixture notes pack (data/scripts/make_fixtures.py: the dictionary and
  # key-term searches below, the ANE entries of Exodus 31, John 3 and
  # Genesis 15 and 38, the theology content of Psalm 82 and the
  # atonement_models theme).
  use ExUnit.Case, async: true

  alias Bezalel.Study.Tools.{
    GetAneContext,
    GetBibleDictionary,
    GetKeyTerms,
    GetStudyNotes,
    GetTheologyContext,
    ListResearchSources
  }

  defp ok(tool, args) do
    assert {:ok, text} = tool.run(args, %{})
    text
  end

  defp error(tool, args) do
    assert {:error, text} = tool.run(args, %{})
    text
  end

  defp headings(text, level),
    do: for([_, h] <- Regex.scan(~r/^#{level} (.+)$/m, text), do: h)

  # The text from `heading` to the next heading of its level, or the end.
  defp section(text, heading) do
    [_, rest] = String.split(text, heading <> "\n", parts: 2)
    rest |> String.split(~r/^# /m, parts: 2) |> hd()
  end

  describe "get_study_notes" do
    test "a verse's notes include the ranges covering it, grouped by source" do
      text = ok(GetStudyNotes, %{"reference" => "John 3:16"})

      assert text =~
               ~r/\A## Study Notes: John 3:16\n\n### Tyndale Study Notes\n\n\*\*John 1:19–12.50\*\*\n/

      assert text =~ "\n**John 3:16**\n"
      assert text =~ "\n**John 3:16–21**\n"
      assert text =~ "### Translation Notes (SIL)\n\n**John 3:16**\n"
      assert text =~ "### Translation Notes (unfoldingWord)\n\n**John 3:16 (#7)**\n"
      refute text =~ "**John 3:14–15**"

      in_range = ok(GetStudyNotes, %{"reference" => "John 3:15"})
      assert in_range =~ "**John 3:14–15**"
      refute in_range =~ "**John 3:16**"
    end

    test "a chapter's notes are those starting in it; chapter_only reads a verse's chapter" do
      chapter = ok(GetStudyNotes, %{"reference" => "John 3"})
      assert chapter =~ "\n**John 3:1**\n"
      assert chapter =~ "\n**John 3:16**\n"
      refute chapter =~ "John 1:19–12.50"

      whole = ok(GetStudyNotes, %{"reference" => "John 3:16", "chapter_only" => true})
      assert whole =~ ~r/\A## Study Notes: John 3:16\n/
      assert whole =~ "\n**John 3:1**\n"
    end

    test "result/1 carries the notes and the spans they cover" do
      {:ok, %{notes: notes}} = GetStudyNotes.result(%{"reference" => "John 3:15"})

      assert %{resource_type: "study_notes", start_ref: "43003014", end_ref: "43003015"} =
               Enum.find(notes, &(&1.title == "John 3:14–15"))

      assert Enum.map(notes, & &1.resource_type) |> Enum.uniq() ==
               ["study_notes", "translation_notes_sil", "translation_notes_uw"]
    end

    test "nothing found, and references it can't read" do
      assert ok(GetStudyNotes, %{"reference" => "John 25:1"}) ==
               "No study notes found for John 25:1."

      # Jude 3 is Jude 1:3 (the fixture keeps no notes on Jude).
      assert ok(GetStudyNotes, %{"reference" => "Jude 3"}) == "No study notes found for Jude 1:3."

      assert error(GetStudyNotes, %{"reference" => "not a reference"}) ==
               "No study notes found for not a reference."

      assert error(GetStudyNotes, %{"reference" => "Tobit 1:1"}) ==
               "No study notes found for Tobit 1:1."

      assert error(GetStudyNotes, %{"reference" => ""}) =~ "Please provide a Bible reference"

      # A chapter past SQLite's 64-bit integers can't be looked up.
      assert error(GetStudyNotes, %{"reference" => "Psalm 9223372036854775808"}) ==
               "No study notes found for Psalm 9223372036854775808."

      assert {:ok, _} = GetStudyNotes.run(%{"reference" => "Psalm 99999999999999999999:1"}, %{})
    end
  end

  describe "get_bible_dictionary" do
    test "an exact title wins over articles mentioning it" do
      text = ok(GetBibleDictionary, %{"topic" => "abraham"})
      assert text =~ ~r/\A## Abraham\n\nABRAHAM\n/
      assert headings(text, "##") == ["Abraham"]
    end

    test "else the first ten title or text matches, titles first and shortest first" do
      text = ok(GetBibleDictionary, %{"topic" => "jubilee"})
      assert ["Jubilee Year", "Book of Jubilees" | others] = headings(text, "##")
      assert Enum.count(others) == 8
      assert "Sabbath" in others
    end

    test "long articles are cut" do
      text = ok(GetBibleDictionary, %{"topic" => "Tabernacle"})

      assert String.ends_with?(
               text,
               "\n\n*[Article truncated — full text available in the Tyndale Bible Dictionary]*\n"
             )

      assert String.length(text) < 4300
    end

    test "nothing found, and no topic" do
      assert ok(GetBibleDictionary, %{"topic" => "zzzz"}) ==
               "No dictionary article found for 'zzzz'."

      assert error(GetBibleDictionary, %{"topic" => ""}) == "Please provide a topic to look up."
    end
  end

  describe "get_key_terms" do
    test "every entry with the exact title" do
      text = ok(GetKeyTerms, %{"term" => "Atonement"})
      assert headings(text, "##") == ["atonement", "atonement"]
      assert text =~ ~r/\A## atonement\n\nt258: atone\/atonement\n/
      assert {:ok, %{terms: [_, _]}} = GetKeyTerms.result(%{"term" => "grace"})
    end

    test "a dictionary article is not a key term; no term" do
      refute ok(GetKeyTerms, %{"term" => "abraham"}) =~ "ABRAHAM"
      assert ok(GetKeyTerms, %{"term" => "zzzz"}) == "No key term found for 'zzzz'."
      assert error(GetKeyTerms, %{"term" => ""}) == "Please provide a term to look up."
    end
  end

  describe "get_ane_context" do
    test "direct entries in full, whole-book entries brief, those not citing the book dropped" do
      text = ok(GetAneContext, %{"reference" => "Genesis 15:6"})
      assert text =~ ~r/\A## Ancient Near East Context for Genesis 15:6\n\n# Directly Relevant/
      direct = section(text, "# Directly Relevant to This Passage")
      broad = section(text, "# General ANE Reading Frame")

      assert direct =~
               "### Covenant Ratification Rituals and Animal Cutting\n*Period: Patriarchal Period"

      assert direct =~ "**ANE Parallels:**"
      assert broad =~ "### Food, Diet, and Communal Meals\n\n"
      refute broad =~ "*Period:"
      refute broad =~ "**ANE Parallels:**"

      for dropped <- ["Agriculture and the Seasonal Cycle", "Oral Culture and Memory"],
          do: refute(text =~ dropped)
    end

    test "a whole-book entry whose key references cite the chapter is promoted" do
      {:ok, %{entries: entries}} = GetAneContext.result(%{"reference" => "Genesis 38:24"})
      assert %{match_type: "direct"} = Enum.find(entries, &(&1.id == "gender_002"))
      assert %{match_type: "broad"} = Enum.find(entries, &(&1.id == "gender_001"))

      direct =
        section(
          ok(GetAneContext, %{"reference" => "Genesis 38:24"}),
          "# Directly Relevant to This Passage"
        )

      assert direct =~ "### The Patriarchal Household (Bet Av)\n*Period:"
    end

    test "detail levels" do
      full = ok(GetAneContext, %{"reference" => "Genesis 15:6", "detail_level" => "full"})
      refute full =~ "# General ANE Reading Frame"
      assert full =~ "### Food, Diet, and Communal Meals\n*Period:"

      brief = ok(GetAneContext, %{"reference" => "Genesis 15:6", "detail_level" => "brief"})
      refute brief =~ "*Period:"
      assert brief =~ "### Covenant Ratification Rituals and Animal Cutting\n\n"
    end

    test "with no arguments, the dimensions and periods" do
      text = ok(GetAneContext, %{})
      assert text =~ ~r/\A## Ancient Near East Context — Available Dimensions\n/
      assert text =~ "- **Legal & Covenant** (`legal_covenant`) — 4 entries\n"
      assert text =~ "- `patriarchal` — Patriarchal Period (c. 2000-1550 BC)\n"
    end

    test "dimension and period filters" do
      assert headings(ok(GetAneContext, %{"dimension" => "legal_covenant"}), "###") == [
               "Suzerainty Treaty Form and Deuteronomy",
               "Covenant Ratification Rituals and Animal Cutting",
               "Land Sale, Inheritance, and Redemption Law",
               "Royal Grants vs. Suzerainty Treaties"
             ]

      assert headings(
               ok(GetAneContext, %{
                 "dimension" => "cosmology_worldview",
                 "period" => "patriarchal"
               }),
               "###"
             ) == ["Hebrew vs Greek Anthropology: Nephesh and Ruach"]
    end

    test "reference forms" do
      for reference <- ["Gen. 15:6", "Genesis 15", "Gen.15.6"] do
        direct =
          section(
            ok(GetAneContext, %{"reference" => reference}),
            "# Directly Relevant to This Passage"
          )

        assert direct =~ "### Covenant Ratification Rituals and Animal Cutting"
      end
    end

    test "nothing found, and input it can't read" do
      assert ok(GetAneContext, %{"reference" => "Genesis 15:6", "dimension" => "warfare_military"}) ==
               "No ANE context entries found for reference=Genesis 15:6, dimension=warfare_military."

      assert error(GetAneContext, %{"reference" => "Gen. fifteen"}) ==
               "No ANE context entries found for reference=Gen. fifteen."

      assert error(GetAneContext, %{"dimension" => "bogus"}) ==
               "No ANE context entries found for dimension=bogus."

      assert error(GetAneContext, %{"period" => "bogus"}) =~ "period=bogus"

      for reference <- ["Psalm 99999999999999999999:1", "Psalm 9223372036854775808"],
          do:
            assert(error(GetAneContext, %{"reference" => reference}) =~ "reference=#{reference}.")
    end

    test "key references' books and chapters" do
      chapters = fn refs -> GetAneContext.key_chapters(JSON.encode!(refs)) end

      assert chapters.(["Gen 38:6-26", "Gen 1:1-2:3", "Deut 25:5-10"]) ==
               MapSet.new([{"Gen", 38}, {"Gen", 1}, {"Deu", 25}])

      assert chapters.(["1 Cor 12:12-27", "Psalm 104:2-3", "Genesis 12:1-3"]) ==
               MapSet.new([{"1Co", 12}, {"Psa", 104}, {"Gen", 12}])

      assert chapters.(["Isaiah 40:1-2", "Isa 53:4-6"]) == MapSet.new([{"Isa", 40}, {"Isa", 53}])
      assert chapters.(["something weird", "Gen 3:15"]) == MapSet.new([{"Gen", 3}])
      assert chapters.([]) == MapSet.new()
      assert GetAneContext.key_chapters(["Gen 1:1"]) == MapSet.new([{"Gen", 1}])
    end
  end

  describe "get_theology_context" do
    test "a verse's entries: primary matches first, then by id; themes sorted" do
      {:ok, %{entries: entries}} =
        GetTheologyContext.result(%{"reference" => "Psalm 82:6", "limit" => 20})

      assert Enum.map(entries, & &1.id) == [8, 10, 23, 35, 37, 38, 39, 25]
      assert entries |> Enum.map(& &1.relevance) |> Enum.uniq() == ["primary", "supporting"]
      assert Enum.all?(entries, &(&1.themes == Enum.sort(&1.themes)))

      text = ok(GetTheologyContext, %{"reference" => "Psalm 82:6"})
      assert text =~ ~r/\A## Theological Scholarship Context for Psalm 82:6\n\n### /
      assert [_, _, _, _] = headings(text, "###")
      assert text =~ "**Matched Reference**: Psa.82.6\n"
      assert String.ends_with?(text, "with a link to the free text.*\n")
    end

    test "a verse no entry is indexed to falls back to its chapter, each entry at its best match" do
      {:ok, %{entries: entries}} =
        GetTheologyContext.result(%{"reference" => "Psalm 82:9", "limit" => 20})

      assert Enum.count(entries) == 16
      ranks = Enum.map(entries, &{&1.relevance != "primary", &1.matched_ref})
      assert Enum.take(ranks, 1) == [{false, "Psa.82.1"}]
      # Entry 1 is indexed only as supporting.
      assert %{relevance: "supporting"} = List.last(entries)
    end

    test "a theme's entries alternate between authors" do
      ids = fn args ->
        {:ok, %{entries: entries}} = GetTheologyContext.result(args)
        Enum.map(entries, &{&1.source_author, &1.id})
      end

      assert ids.(%{"theme" => "atonement_models"}) ==
               [{"stott", 109}, {"synthesis", 59}, {"stott", 131}, {"synthesis", 60}]

      assert Enum.count(ids.(%{"theme" => "atonement_models", "limit" => 10})) == 9

      assert ids.(%{"theme" => "atonement_models", "author" => "stott"})
             |> Enum.map(&elem(&1, 0))
             |> Enum.uniq() ==
               ["stott"]

      assert ok(GetTheologyContext, %{"theme" => "atonement_models", "author" => "stott"}) =~
               ~r/\A## Stott Scholarship Context — theme: atonement_models\n\n/
    end

    test "with neither reference nor theme, the themes (an author's own with an author)" do
      assert ok(GetTheologyContext, %{}) =~ ~r/\A## Theological Themes\n\n### .+ \(`\w+`\)\n/

      {:ok, %{themes: themes}} = GetTheologyContext.result(%{"author" => "heiser"})
      assert "divine_council" in Enum.map(themes, & &1.key)
      refute "atonement_models" in Enum.map(themes, & &1.key)
    end

    test "nothing found, and input it can't act on" do
      assert ok(GetTheologyContext, %{"reference" => "Genesis 6:2", "author" => "owen"}) ==
               "No theological scholarship found for reference='Genesis 6:2' (author='owen')."

      assert error(GetTheologyContext, %{"author" => "nobody"}) ==
               "No scholarship data found for author 'nobody'."

      assert error(GetTheologyContext, %{"theme" => "bogus"}) ==
               "No theological scholarship found for theme='bogus'."

      assert error(GetTheologyContext, %{"reference" => "Psalm 82"}) ==
               "No theological scholarship found for reference='Psalm 82'."

      assert error(GetTheologyContext, %{"reference" => "Psalm 99999999999999999999:1"}) ==
               "No theological scholarship found for reference='Psalm 99999999999999999999:1'."
    end
  end

  describe "list_research_sources" do
    defp keys(topic, perspective \\ nil),
      do: Enum.map(ListResearchSources.find(topic, perspective), & &1["key"])

    defp source(key), do: Enum.find(ListResearchSources.catalogue(), &(&1["key"] == key))

    test "the catalogue's listings are usable" do
      catalogue = ListResearchSources.catalogue()
      assert Enum.count(catalogue) in 20..40
      assert catalogue |> Enum.uniq_by(& &1["key"]) == catalogue

      for s <- catalogue do
        for field <- ~w(key name url description perspective access),
            do: assert(s[field] =~ ~r/\S/)

        assert s["url"] =~ ~r/^https?:\/\//
        assert [_ | _] = s["coverage"]
        assert Date.from_iso8601!(s["last_verified"])
        template = s["search_url_template"]
        assert template == nil or match?([_, _], String.split(template, "{query}"))
      end
    end

    test "topics match tags, phrases containing a tag, aliases and names" do
      assert MapSet.subset?(
               MapSet.new(~w(sefaria alhatorah mechon_mamre)),
               MapSet.new(keys("rabbinic"))
             )

      assert Enum.all?(keys("rabbinic"), &("rabbinic" in source(&1)["coverage"]))
      assert "sefaria" in keys("rabbinic commentary")
      refute "tyndale_bulletin" in keys("rabbinic commentary")

      assert MapSet.subset?(
               MapSet.new(~w(leon_levy_dss orion_bibliography)),
               MapSet.new(keys("DSS"))
             )

      assert hd(keys("Sefaria")) == "sefaria"
      assert keys("quantum chromodynamics") == []
    end

    test "perspective is case-insensitive and partial, and combines with topic" do
      reformed = ListResearchSources.find(nil, "reformed")
      assert reformed != [] and Enum.all?(reformed, &(&1["perspective"] == "Reformed"))
      academic = ListResearchSources.find(nil, "Academic")
      assert academic != [] and Enum.all?(academic, &(&1["perspective"] == "academic/critical"))
      assert keys("church fathers", "catholic") == ["new_advent_fathers"]
    end

    test "search links are URL-encoded and can't break the template's parameters" do
      assert ListResearchSources.search_url(source("sefaria"), "sons of God & Psalm 82") ==
               "https://www.sefaria.org/search?q=sons+of+God+%26+Psalm+82"

      params =
        source("jstor_early_journal_content")
        |> ListResearchSources.search_url("a&and[]=x #frag")
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.query_decoder()
        |> Enum.to_list()

      assert {"query", "a&and[]=x #frag"} in params
      assert {"and[]", ~s(collection:"jstor_ejc")} in params
      assert ListResearchSources.search_url(source("mechon_mamre"), "Psalm 82") == nil
    end

    test "the tool: filters, search links, limits and the empty case" do
      text = ok(ListResearchSources, %{"topic" => "rabbinic", "query" => "Psalm 82"})
      assert text =~ ~r/\A## Research Sources \(topic: rabbinic; query: Psalm 82\)\n/
      assert text =~ "not endorsements"
      assert text =~ "### Sefaria\n"
      assert text =~ "https://www.sefaria.org/search?q=Psalm+82"
      assert text =~ "- **Search**: no linkable search"
      refute text =~ "Tyndale Bulletin"

      total = length(ListResearchSources.catalogue())
      default = ok(ListResearchSources, %{})
      assert default =~ "Showing 4 of #{total} matching sources."
      assert [_, _, _, _] = headings(default, "###")
      assert [_, _, _] = headings(ok(ListResearchSources, %{"limit" => 3}), "###")
      assert Enum.count(headings(ok(ListResearchSources, %{"limit" => 50}), "###")) == 10
      assert [_] = headings(ok(ListResearchSources, %{"limit" => -2}), "###")

      none = ok(ListResearchSources, %{"topic" => "quantum chromodynamics"})
      assert none =~ "No sources match these filters."
      assert none =~ "dead sea scrolls"
    end

    test "the verification date shown is the oldest listed" do
      sources = [
        Map.put(source("sefaria"), "last_verified", "2026-10-12"),
        Map.put(source("ccel"), "last_verified", "2026-01-05")
      ]

      text =
        ListResearchSources.render(%{
          topic: nil,
          query: nil,
          perspective: nil,
          total: 2,
          sources: sources
        })

      assert String.ends_with?(text, "*Listings verified on or after 2026-01-05.*")
    end
  end
end
