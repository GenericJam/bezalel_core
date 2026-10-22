defmodule Bezalel.Study.Tools.LexiconToolsTest do
  # word_study, search_lexicon, search_by_strongs and parse_morphology,
  # ported from studybible-mcp's tests/test_tool_handlers.py and
  # tests/test_strongs.py, against the fixture packs. The fixture keeps the
  # ten entries the full lexicon ranks first for 'love', 'wisdom' and
  # 'craftsman', so those rankings are the real pack's.
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Citation, DB, Lexicon, Preferences, Translations, Verses}
  alias Bezalel.Study.Tools.{ParseMorphology, SearchByStrongs, SearchLexicon, WordStudy}

  # studybible-mcp's default of four results, and the BSB.
  @prefs Preferences.new(limit: 4, translation: "bsb")

  defp ok(ParseMorphology, args) do
    assert {:ok, {:details, text, %{citations: [_]}}} = ParseMorphology.run(args, %{})
    text
  end

  defp ok(tool, args) do
    assert {:ok, result} = tool.result(args, @prefs)
    tool.render(result)
  end

  defp error(tool, args) do
    assert {:error, message} = tool.run(args, %{})
    message
  end

  defp verse_hits(text) do
    for [_, ref] <- Regex.scan(~r/^\*\*([1-3]?[A-Za-z]{2,3}\.\d+\.\d+\S*)\*\*/m, text), do: ref
  end

  defp lexicon_hits(text), do: for([_, s] <- Regex.scan(~r/^### ([GH]\d{4}) - /m, text), do: s)

  describe "word_study" do
    test "the Exodus 31 words: rûaḥ, ḥokmâ, mālēʾ and Bezalel, each with Exodus 31 among its examples" do
      ruach = ok(WordStudy, %{"strongs" => "H7307"})
      assert ruach =~ ~r/\A## H7307 - \S+\n\*\*Transliteration\*\*: ruach\n/
      assert ruach =~ "**Language**: Hebrew"
      assert ruach =~ "### Full BDB Definition"
      assert ruach =~ "## Example Passages (BSB)"
      # The first five verses with the number, in canonical order.
      assert verse_hits(ruach) == [
               "Gen.1.2",
               "Exo.31.3",
               "Exo.35.31",
               "Ezk.27.26",
               "Jol.2.28(3.1)"
             ]

      hokmah = ok(WordStudy, %{"strongs" => "H2451"})
      assert hokmah =~ ~r/\A## H2451 - \S+\n\*\*Transliteration\*\*: chokmah\n/
      assert "Exo.31.3" in verse_hits(hokmah)
      assert hokmah =~ "**Exo.31.3**: And I have filled him with the Spirit of God, with skill"

      male = ok(WordStudy, %{"strongs" => "H4390"})
      assert male =~ ~r/\A## H4390 - \S+\n\*\*Transliteration\*\*: male\n/
      assert male =~ "be full, fill"
      assert "Exo.31.3" in verse_hits(male)

      bezalel = ok(WordStudy, %{"strongs" => "H1212"})
      assert bezalel =~ "proper name, masculine"
      assert verse_hits(bezalel) == ["Exo.31.2", "Exo.35.30", "Exo.36.1", "Exo.36.2"]
    end

    test "Strong's numbers are normalized; a sense-suffixed number uses the bare entry" do
      assert ok(WordStudy, %{"strongs" => "h1212"}) =~ ~r/\A## H1212 - /
      # lookup_verse shows Bezalel as H1212G; the lexicon is keyed H1212.
      assert ok(WordStudy, %{"strongs" => "H1212G"}) =~ ~r/\A## H1212 - /

      assert ok(WordStudy, %{"strongs" => "G26"}) =~
               ~r/\A## G0026 - \S+\n\*\*Transliteration\*\*: agap/
    end

    test "a word resolves to the most relevant entry in the given language (Greek by default)" do
      assert ok(WordStudy, %{"word" => "love"}) =~ ~r/\A## G0025 - /
      assert ok(WordStudy, %{"word" => "wisdom", "language" => "hebrew"}) =~ ~r/\A## H2451 - /
    end

    test "no match, and no argument" do
      assert error(WordStudy, %{"strongs" => "G9999"}) ==
               "No entry found for the given word/Strong's number."

      assert ok(WordStudy, %{"word" => "zzzz"}) ==
               "No entry found for the given word/Strong's number."

      assert error(WordStudy, %{}) ==
               "Please provide either 'strongs' number or 'word' to study."
    end

    test "the entry cites its lexicons and Strong's page, the UBS entry, each example its verse" do
      assert {:ok, ruach} = WordStudy.result(%{"strongs" => "H7307"}, @prefs)

      assert [
               %Citation{work: "step", url: "https://www.stepbible.org/?q=strong=H7307"},
               %Citation{work: "bdb", url: "https://biblehub.com/bdb/7307.htm"},
               %Citation{work: "strongs", url: "https://biblehub.com/hebrew/7307.htm"},
               %Citation{work: "ubs_hebrew"} = ubs,
               %Citation{work: "bsb", url: "https://biblehub.com/genesis/1-2.htm"}
               | examples
             ] = citations = WordStudy.citations(ruach)

      assert Enum.count(examples) == 4
      text = WordStudy.render(ruach)

      # The entry's Source line closes the entry, then the UBS entry closes
      # with its own; an example's sits under it.
      assert text =~
               "\n" <>
                 Citation.source_line(Enum.take(citations, 3)) <>
                 "\n\n## UBS Dictionary of Biblical Hebrew: "

      assert text =~ "\n" <> Citation.source_line(ubs) <> "\n\n## Example Passages (BSB)"

      assert text =~
               ~r/\n\*\*Gen\.1\.2\*\*: [^\n]+\nSource: \[Genesis 1:2\]\(https:\/\/biblehub\.com\/genesis\/1-2\.htm\)\n/

      assert {:ok, {:details, _text, %{citations: run_citations, entry: %{"strongs" => "H7307"}}}} =
               WordStudy.run(%{"strongs" => "H7307"}, %{})

      assert %Citation{url: "https://biblehub.com/bdb/7307.htm"} =
               Enum.find(run_citations, &(&1.work == "bdb"))

      # Greek: LSJ for the full entry, Abbott-Smith's, and the Strong's page.
      assert {:ok, agape} = WordStudy.result(%{"strongs" => "G26"}, @prefs)

      assert [
               %Citation{work: "step"},
               %Citation{work: "lsj", url: "https://lsj.gr/wiki/" <> _},
               %Citation{work: "abbott_smith", url: "https://archive.org/details/" <> _},
               %Citation{work: "strongs", url: "https://biblehub.com/greek/26.htm"} | _
             ] = WordStudy.citations(agape)

      assert WordStudy.citations(%{entry: nil}) == []
    end
  end

  describe "search_lexicon" do
    test "ranks matches in both languages, gloss matches first, then by usage" do
      text = ok(SearchLexicon, %{"query" => "love"})
      assert text =~ ~r/\A## Lexicon Search: 'love'\n\nFound 4 entries:\n\n/
      assert lexicon_hits(text) == ["H0157", "G0025", "G0026", "G0027"]

      assert text =~
               ~r/^### G0026 - \S+ \(agap.\)\nlove\nSource: \[STEP lexicon G0026 \S+\]\(https:\/\/www\.stepbible\.org\/\?q=strong=G0026\) · \[Strong's G26 \S+\]\(https:\/\/biblehub\.com\/greek\/26\.htm\)\n\n/mu
    end

    test "each entry cites the brief lexicon its definition comes from and its Strong's page" do
      assert {:ok, result} = SearchLexicon.result(%{"query" => "love"}, @prefs)

      assert [
               %Citation{work: "step", url: "https://www.stepbible.org/?q=strong=H0157"},
               %Citation{work: "strongs", url: "https://biblehub.com/hebrew/157.htm"} | _
             ] = citations = SearchLexicon.citations(result)

      assert Enum.count(citations, &(&1.work == "strongs")) == 4

      assert {:ok, {:details, text, %{citations: ^citations}}} =
               SearchLexicon.run(%{"query" => "love", "limit" => 4}, %{})

      assert text =~ "Source: [STEP lexicon H0157"
    end

    test "the language filter and a larger limit" do
      text = ok(SearchLexicon, %{"query" => "love", "language" => "greek", "limit" => 6})
      assert lexicon_hits(text) == ["G0025", "G0026", "G0027", "G5368", "G5360", "G4375"]

      assert lexicon_hits(ok(SearchLexicon, %{"query" => "wisdom", "language" => "hebrew"}))
             |> hd() == "H2451"
    end

    test "no match, and an empty query" do
      assert ok(SearchLexicon, %{"query" => "zzzz"}) == "No entries found for 'zzzz'."
      assert error(SearchLexicon, %{"query" => ""}) == "Please provide a search query."
    end
  end

  describe "search_by_strongs" do
    test "the default cap is the user's limit (four here), in canonical order" do
      text = ok(SearchByStrongs, %{"strongs" => "H7307"})

      assert text =~
               ~r/\A## Verses with H7307 \(\S+ - ruach\) \(BSB\)\n\n\*masculine\*\nSource: \[STEP lexicon H7307 \S+\]\(https:\/\/www\.stepbible\.org\/\?q=strong=H7307\) · \[Strong's H7307 \S+\]\(https:\/\/biblehub\.com\/hebrew\/7307\.htm\)\n\n/

      # Each verse cites its BSB page, on the line under it.
      assert text =~
               ~r/^\*\*Exo\.31\.3\*\*: And I have filled him [^\n]+\nSource: \[Exodus 31:3\]\(https:\/\/biblehub\.com\/exodus\/31-3\.htm\)\n\n/m

      assert verse_hits(text) == ["Gen.1.2", "Exo.31.3", "Exo.35.31", "Ezk.27.26"]
    end

    test "the entry and the verses shown are the citations, in order" do
      assert {:ok, result} = SearchByStrongs.result(%{"strongs" => "H7307"}, @prefs)

      assert [
               %Citation{work: "step"},
               %Citation{work: "strongs", url: "https://biblehub.com/hebrew/7307.htm"},
               %Citation{work: "bsb", url: "https://biblehub.com/genesis/1-2.htm"},
               %Citation{work: "bsb", url: "https://biblehub.com/exodus/31-3.htm"},
               %Citation{work: "bsb"},
               %Citation{work: "bsb", url: "https://biblehub.com/ezekiel/27-26.htm"}
             ] = SearchByStrongs.citations(result)

      assert {:ok, {:details, _text, %{citations: [_ | _]}}} =
               SearchByStrongs.run(%{"strongs" => "H7307"}, %{})
    end

    test "the default cap is 8 unless the user changes it" do
      assert {:ok, %{verses: verses}} =
               SearchByStrongs.result(
                 %{"strongs" => "H7307"},
                 Preferences.new(translation: "bsb")
               )

      # The fixture holds six verses with H7307, all within the default 8.
      assert Enum.count(verses) == 6

      assert {:ok, %{verses: [_, _]}} =
               SearchByStrongs.result(%{"strongs" => "H7307"}, Preferences.new(limit: 2))
    end

    test "a bare number finds every sense; a suffixed number only its own" do
      all = verse_hits(ok(SearchByStrongs, %{"strongs" => "H7307", "limit" => 20}))
      assert Enum.count(all) == 6
      # Ezekiel 27:26's rûaḥ is H7307H (wind); the others are H7307G (spirit).
      spirit = verse_hits(ok(SearchByStrongs, %{"strongs" => "H7307G", "limit" => 20}))
      assert spirit == all -- ["Ezk.27.26"]
      assert verse_hits(ok(SearchByStrongs, %{"strongs" => "H7307H"})) == ["Ezk.27.26"]
    end

    test "a number does not match a longer number" do
      # Exodus 31:2 has H0221G (Uri) but not H0022 ('H22').
      {:ok, refs} =
        DB.with_pack(:core, fn conn ->
          conn
          |> Verses.with_strongs("H22", 1000, Translations.get("bsb"))
          |> Enum.map(& &1["reference"])
        end)

      refute "Exo.31.2" in refs
      assert "Exo.31.2" in verse_hits(ok(SearchByStrongs, %{"strongs" => "H221", "limit" => 50}))
    end

    test "an unknown number and no number are errors" do
      assert error(SearchByStrongs, %{"strongs" => "G9999"}) == "Unknown Strong's number: G9999"

      assert error(SearchByStrongs, %{"strongs" => ""}) ==
               "Please provide a Strong's number (e.g., 'G26' or 'H3068')."
    end
  end

  describe "parse_morphology" do
    test "a Greek verb and noun" do
      verb = ok(ParseMorphology, %{"code" => "V-AAI-3S"})

      assert verb =~
               ~r/\A## Morphology: V-AAI-3S\n\n\*\*Language\*\*: Greek\n\*\*Part of Speech\*\*: Verb\n/

      for line <- [
            "**Person**: 3rd",
            "**Number**: Singular",
            "**Tense**: Aorist",
            "**Voice**: Active",
            "**Mood**: Indicative"
          ] do
        assert verb =~ line
      end

      noun = ok(ParseMorphology, %{"code" => "N-GSF"})
      assert noun =~ "**Case**: Genitive" and noun =~ "**Gender**: Feminine"
      refute noun =~ "**Tense**"
    end

    test "the parsing cites STEPBible's morphology codes" do
      assert {:ok, {:details, text, %{citations: [citation]}}} =
               ParseMorphology.run(%{"code" => "V-AAI-3S"}, %{})

      assert %Citation{
               work: "step",
               locator: "V-AAI-3S",
               url: "https://github.com/STEPBible/STEPBible-Data"
             } = citation

      assert String.ends_with?(text, "\n" <> Citation.source_line(citation) <> "\n")
    end

    test "the language argument" do
      hebrew = ok(ParseMorphology, %{"code" => "HVqp3ms", "language" => "hebrew"})
      assert hebrew =~ "**Language**: Hebrew"
      assert hebrew =~ "Stem=Qal"
      # The Greek code is not a Hebrew code.
      assert error(ParseMorphology, %{"code" => "V-AAI-3S", "language" => "hebrew"}) ==
               "Unknown morphology code: V-AAI-3S"
    end

    test "an unknown and an empty code" do
      assert error(ParseMorphology, %{"code" => "X-YYY"}) == "Unknown morphology code: X-YYY"

      assert error(ParseMorphology, %{"code" => ""}) ==
               "Please provide a morphology code to parse."
    end
  end

  # The real core pack keys 455 Abbott-Smith entries by lemma ("AS_ἀγγέλλω",
  # no Strong's number); search_lexicon used to crash on them.
  test "an entry with no Strong's number cites Abbott-Smith alone" do
    entry = %{
      "strongs" => "AS_ἀγγέλλω",
      "word" => "ἀγγέλλω",
      "short_definition" => "to announce",
      "full_definition" => "to announce, report",
      "abbott_smith_def" => "to announce, report"
    }

    for shown <- [:brief, :full] do
      assert [%Citation{work: "abbott_smith", url: url}] = WordStudy.entry_citations(entry, shown)
      assert url =~ "/page/4/"
    end
  end

  # word_study upper-cased the key, so 436 of the 455 ('AS_ῥοπή' became
  # 'AS_ῬΟΠΉ') were "No entry found".
  test "an Abbott-Smith key keeps its lemma's case" do
    assert Lexicon.normalize_strongs(" as_ῥοπή ") == "AS_ῥοπή"
    assert Lexicon.normalize_strongs("g26") == "G0026"
    assert Lexicon.normalize_strongs("h430g") == "H0430G"
  end
end
