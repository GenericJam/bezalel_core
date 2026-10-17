defmodule Bezalel.Study.Tools.LexiconToolsTest do
  # word_study, search_lexicon, search_by_strongs and parse_morphology,
  # ported from studybible-mcp's tests/test_tool_handlers.py and
  # tests/test_strongs.py, against the fixture packs. The fixture keeps the
  # ten entries the full lexicon ranks first for 'love', 'wisdom' and
  # 'craftsman', so those rankings are the real pack's.
  use ExUnit.Case, async: true

  alias Bezalel.Study.{DB, Verses}
  alias Bezalel.Study.Tools.{ParseMorphology, SearchByStrongs, SearchLexicon, WordStudy}

  # word_study answers with its data too (rho's tool details); the others with text.
  defp ok(tool, args) do
    case tool.run(args, %{}) do
      {:ok, {:details, text, _result}} -> text
      {:ok, text} when is_binary(text) -> text
    end
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
  end

  describe "search_lexicon" do
    test "ranks matches in both languages, gloss matches first, then by usage" do
      text = ok(SearchLexicon, %{"query" => "love"})
      assert text =~ ~r/\A## Lexicon Search: 'love'\n\nFound 4 entries:\n\n/
      assert lexicon_hits(text) == ["H0157", "G0025", "G0026", "G0027"]
      assert text =~ ~r/^### G0026 - \S+ \(agap.\)\nlove\n\n/mu
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
    test "the default cap is four verses, in canonical order" do
      text = ok(SearchByStrongs, %{"strongs" => "H7307"})
      assert text =~ ~r/\A## Verses with H7307 \(\S+ - ruach\) \(BSB\)\n\n\*masculine\*\n\n/
      assert verse_hits(text) == ["Gen.1.2", "Exo.31.3", "Exo.35.31", "Ezk.27.26"]
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
          conn |> Verses.with_strongs("H22", 1000) |> Enum.map(& &1["reference"])
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
end
