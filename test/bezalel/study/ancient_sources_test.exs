defmodule Bezalel.Study.Tools.AncientSourcesTest do
  # search_ancient_sources and lookup_ancient_source, ported from
  # studybible-mcp's test_ancient_sources.py, test_ancient_corpora.py,
  # test_ancient_labelling.py and the per-corpus test files (handler,
  # formatter, citation and locator cases) against the fixture ancient pack,
  # which keeps the passages these tests cite (make_fixtures.py
  # ANCIENT_CITATIONS) and those linked to the fixture chapters.
  use ExUnit.Case, async: true

  alias Bezalel.Study.Ancient
  alias Bezalel.Study.Ancient.Passages
  alias Bezalel.Study.Tools.{LookupAncientSource, SearchAncientSources}

  defp search(args), do: SearchAncientSources.run(args, %{})
  defp lookup(args), do: LookupAncientSource.run(args, %{})

  defp ok(result) do
    assert {:ok, text} = result
    text
  end

  defp error(result) do
    assert {:error, text} = result
    text
  end

  defp headings(text), do: for([_, h] <- Regex.scan(~r/^### (.+)$/m, text), do: h)

  defp resolved(citation) do
    assert {:ok, match} = Ancient.resolve(citation, Ancient.corpora())
    {match.corpus.key, match.work.key, match.sort_range}
  end

  describe "search_ancient_sources" do
    test "stems English, folds Greek accents and case, and combines filters" do
      for query <- ["Herod temple building", "βαπτισμῷ", "βαπτισμω", "ΒΑΠΤΙΣΤΟΥ Ιωαννου"] do
        assert "Flavius Josephus, Antiquities 18.116–119 (Whiston 18.5.2)" in headings(
                 ok(search(%{"query" => query}))
               ),
               query
      end

      {:ok, linked} =
        SearchAncientSources.result(%{
          "query" => "John Baptist",
          "biblical_reference" => "Mark 6:20",
          "period" => "second_temple"
        })

      assert [%{reference: "Antiquities 18.116–119", links: [link | _]}] = linked.passages
      assert link.label == "Shared tradition" and link.note =~ "Related account"

      assert ok(search(%{"query" => "John Baptist", "period" => "hasmonean"})) =~
               "No Josephus passage contains any of the search terms (john, baptist) with filters period=hasmonean."
    end

    test "only passage text is searched, not titles" do
      for query <- ["Apion", "Josephus"] do
        assert ok(search(%{"query" => query})) =~ "No Josephus passage contains any", query
      end
    end

    test "falls back to any term and ignores operators and punctuation" do
      fallback = ok(search(%{"query" => "Vitellius xylophone"}))
      assert fallback =~ "*No passage contains all terms; showing passages matching any term.*"
      assert "Flavius Josephus, Antiquities 18.120–129 (Whiston 18.5.3)" in headings(fallback)

      {:ok, operators} = SearchAncientSources.result(%{"query" => ~s(Vitellius OR NOT "Aretas)})
      assert operators.terms == ["vitellius", "aretas"] and operators.match == "all"

      {:ok, signs} = SearchAncientSources.result(%{"query" => ~s|(Vitel[li]us) {Aretas}*|})
      assert signs.terms == ["vitellius", "aretas"]

      assert error(search(%{"query" => "AND OR"})) =~
               "Search operators (AND, OR, NOT, NEAR) are ignored."

      assert error(search(%{"query" => "  "})) ==
               "Please provide words to search in the ancient source text."
    end

    test "explains each empty result" do
      assert error(search(%{"query" => "John", "biblical_reference" => "Hezekiah 3:1"})) =~
               "Unsupported biblical_reference 'Hezekiah 3:1'"

      no_link = ok(search(%{"query" => "John", "biblical_reference" => "Obadiah 1"}))
      assert no_link =~ "No Josephus passage has an editorial biblical link covering Obadiah 1."
      assert no_link =~ "curated"

      assert ok(search(%{"query" => "xylophone", "corpus" => "all"})) ==
               "No ancient-source passage contains any of the search terms (xylophone)."

      assert error(search(%{"query" => "John", "corpus" => "nonesuch"})) ==
               "Unsupported ancient-source corpus 'nonesuch'. Available corpora: " <>
                 "josephus, targum, qumran, philo, pseudepigrapha, rabbinic, or 'all'."

      assert error(search(%{"query" => "x", "period" => "amoraic"})) =~
               "Unsupported period: amoraic."

      assert error(search(%{"query" => "x", "limit" => 21})) ==
               "'limit' must be an integer from 1 to 20."
    end

    test "corpus=all labels each corpus once and lists the tiers present" do
      text = ok(search(%{"query" => "God", "corpus" => "all", "limit" => 20}))
      assert text =~ "*Filters: corpus=all*"
      [_, closing] = String.split(text, "**Caveats**\n")
      [caveats, _] = String.split(closing, "\n\n**Sources**\n")
      labels = for [_, label] <- Regex.scan(~r/^- (\w+): Not Scripture/m, caveats), do: label
      assert [_, _ | _] = labels
      assert labels == Enum.uniq(labels)
      assert caveats =~ ~r/^- Tier [AB]: /m
    end

    test "Hebrew: points folded, prefix letters only as a marked fallback" do
      pointed = ok(search(%{"query" => "הַשְּׁקָלִים", "corpus" => "rabbinic"}))
      assert "Mishnah Shekalim 1:1" in headings(pointed)

      prefixed = ok(search(%{"query" => "רוחא", "corpus" => "targum"}))

      assert prefixed =~
               "*No exact match: these passages match only after stripping Hebrew/Aramaic prefix"

      assert Enum.all?(headings(prefixed), &String.ends_with?(&1, " (prefix match)"))
    end
  end

  describe "lookup_ancient_source" do
    test "resolves a section inside a Whiston span, with tag, caveat, licence and links" do
      inside = ok(lookup(%{"citation" => "Ant. 18.117"}))
      assert inside =~ ~r/\A## Antiquities 18.117\n/
      assert inside =~ "1 overlapping passage*"

      assert inside =~
               "### Flavius Josephus, Antiquities 18.116–119 (Whiston 18.5.2)\n" <>
                 "*Not Scripture · Jewish history (AD 93–94) · tier A · Niese Greek, Whiston English*"

      assert inside =~ "- Josephus: Not Scripture: a Jewish historian writing c. AD 75–100"
      assert inside =~ "License: CC BY-SA 4.0."
      assert inside =~ "**Greek:** "
      assert inside =~ "- Shared tradition: Mark 6:17–29 — Related account"

      spanning = ok(lookup(%{"citation" => "Josephus, A.J. 18.116-121"}))

      assert headings(spanning) |> Enum.map(&hd(String.split(&1, " ("))) ==
               [
                 "Flavius Josephus, Antiquities 18.116–119",
                 "Flavius Josephus, Antiquities 18.120–129"
               ]

      refute ok(lookup(%{"citation" => "Antiquities 18.116", "include_original" => false})) =~
               "**Greek:**"

      assert ok(lookup(%{"citation" => "Life 1"})) =~ "### Flavius Josephus, Life 1–6 (Whiston 1)"
    end

    test "caps passages and explains failures" do
      capped = ok(lookup(%{"citation" => "Antiquities 18", "limit" => 1}))
      assert capped =~ "*Showing the first 1 of 2 overlapping passages"

      assert error(lookup(%{"citation" => "Antiquities 18", "limit" => 11})) ==
               "'limit' must be an integer from 1 to 10."

      assert error(lookup(%{"citation" => "Ant. 99999999999999999999.1"})) =~
               ~r/\ACould not read the locator '99999999999999999999.1'/

      assert ok(lookup(%{"citation" => "Ant. 18.200"})) ==
               "No passage covers Antiquities 18.200. Imported Antiquities runs Antiquities " <>
                 "1.27–18.129; nearest passages: preceding Antiquities 18.120–129."

      unknown = error(lookup(%{"citation" => "Lifeboat 1-2"}))
      assert unknown =~ ~r/\AUnknown work in citation 'Lifeboat 1-2'\. Citable works:/

      assert unknown =~
               "Josephus (Antiquities, Life, Against Apion, War; e.g. 'Antiquities 18.116')"

      assert unknown =~ "Rabbinic (Mishnah, 63 works; e.g. 'Mishnah Shekalim 1:1')"
      assert String.length(unknown) < 700

      assert error(lookup(%{"citation" => "Antiquites 18.116"})) =~ "Did you mean Antiquities?"

      no_locator = error(lookup(%{"citation" => "Antiquities"}))
      assert no_locator =~ ~r/\ANo locator in 'Antiquities'/
      # The example is the work's first imported passage.
      assert no_locator =~ "cited by book.section, books 1–20); e.g. 'Antiquities 1.27'."

      assert error(lookup(%{"citation" => "Ant. 18.5.2"})) =~
               ~r/\ACould not read the locator '18.5.2'/

      assert error(lookup(%{"citation" => "Ant. 18.116", "corpus" => "nonesuch"})) =~
               ~r/\AUnsupported ancient-source corpus 'nonesuch'/

      assert error(lookup(%{"citation" => ""})) =~
               "Please provide a citation such as 'Antiquities 18.116'"
    end

    test "an out-of-range citation names its neighbours and the gap note" do
      text = ok(lookup(%{"citation" => "4 Ezra 7:50"}))
      assert text =~ "No passage covers 4 Ezra 7:50. Imported 4 Ezra runs 4 Ezra "
      assert text =~ "nearest passages: preceding 4 Ezra 7:35, following 4 Ezra 7:106."
      assert text =~ " ⚠ 4 Ezra 7:35–106: "
    end

    test "a line citation shows the cited lines ±2; an original-only passage says so" do
      {:ok, r} = LookupAncientSource.result(%{"citation" => "1QpHab 8:8-12"})
      assert r.window == %{start: 8006, end: 8014}
      assert r.sort_range == %{start: 8008, end: 8012}
      text = LookupAncientSource.render(r)
      assert text =~ "*Lines 8:6–14 shown (the cited line ±2); cite the column for all of it.*"
      assert text =~ "Hebrew only.*"
      assert text =~ "(non-commercial; https://creativecommons.org/licenses/by-nc/4.0/)"

      refute ok(lookup(%{"citation" => "1QpHab 8"})) =~ "Lines 8:"
    end

    test "every corpus's own citation forms" do
      assert ok(lookup(%{"citation" => "CD 6:11"})) =~ "## CD 6:11\n"
      assert ok(lookup(%{"citation" => "1QS vi 11"})) =~ "(column:line 6:11)"

      assert ok(lookup(%{"citation" => "Onkelos Gen 49:10"})) =~
               "## Targum Onkelos Genesis 49:10\n"

      assert ok(lookup(%{"citation" => "Opif. 26", "full_text" => true})) =~ "## Opif. 26\n"
      assert ok(lookup(%{"citation" => "4 Ezra 7:28"})) =~ "## 4 Ezra 7:28\n"
      assert ok(lookup(%{"citation" => "m. Sukkah 4:9"})) =~ "## Mishnah Sukkah 4:9\n"
      assert ok(lookup(%{"citation" => "Shekalim 1:1"})) =~ "## Mishnah Shekalim 1:1\n"
      assert error(lookup(%{"citation" => "Leg. 31"})) =~ "cited by book.section, books 1–3"
    end
  end

  describe "citations and locators" do
    test "resolve across corpora" do
      assert resolved("Ant. 18.116-119") == {"josephus", "antiquities", {18_116, 18_119}}
      assert resolved("AJ 15.320") == {"josephus", "antiquities", {15_320, 15_320}}

      assert resolved("Josephus, Jewish Antiquities 18.116") ==
               {"josephus", "antiquities", {18_116, 18_116}}

      assert resolved("B.J. 6.316") == {"josephus", "jewish_war", {6316, 6316}}
      assert resolved("Against Apion 2.1") == {"josephus", "against_apion", {2001, 2001}}
      assert resolved("m. B. Bat. 1:1") == {"rabbinic", "mishnah_bava_batra", {1001, 1001}}
      assert resolved("Ta’anit 2:1") == {"rabbinic", "mishnah_taanit", {2001, 2001}}
      assert resolved("4 Ezra 11-12") == {"pseudepigrapha", "4_ezra", {11_000, 12_999}}
      assert resolved("CD VI, 11") == {"qumran", "damascus_document", {6011, 6011}}
      assert resolved("Ant. 18.116–19.5") == {"josephus", "antiquities", {18_116, 19_005}}
      assert Ancient.resolve("Lifeboat 1", Ancient.corpora()) == :unknown_work

      assert {:bad_locator, [%{locator_text: "3b"}]} =
               Ancient.resolve("Mishnah Bava Batra 3b", Ancient.corpora())
    end

    test "locators parse ranges and Roman columns and render collapsed ranges" do
      loc = %{
        name: "book.section",
        example: "18.116",
        depth: 2,
        scale: 1000,
        separator: ".",
        roman: false,
        books: nil
      }

      col = %{loc | name: "column:line", separator: ":", roman: true}
      assert Ancient.parse_locator(loc, "18") == {18_000, 18_999}
      assert Ancient.parse_locator(loc, "18.116-19.5") == {18_116, 19_005}
      assert Ancient.parse_locator(loc, "18.119-116") == nil
      assert Ancient.parse_locator(loc, "18.1000") == nil
      assert Ancient.parse_locator(loc, "1.2.3") == nil
      assert Ancient.parse_locator(col, "VI 11") == {6011, 6011}
      assert Ancient.parse_locator(col, "iiii 1") == nil
      assert Ancient.format_range(loc, 18_000, 18_999) == "18"
      assert Ancient.format_range(loc, 18_116, 18_119) == "18.116–119"
      assert Ancient.format_range(loc, 18_116, 19_005) == "18.116–19.5"
    end

    test "biblical ranges parse and render" do
      assert Ancient.biblical_range("Luke 21") == {"Luk", 21_001, 21_999}
      assert Ancient.biblical_range("Jude 14-15") == {"Jud", 1014, 1015}
      assert Ancient.biblical_range("Hezekiah 3:1") == nil
      assert Ancient.biblical_range("Gen 3:5-2") == nil
      assert Ancient.biblical_range("Gen 201") == nil
      assert Ancient.parse_passage_reference("Psalm 1:99999999999999999999") == nil
      assert Ancient.parse_passage_reference("Psalm 99999999999999999999") == nil

      assert Ancient.parse_passage_reference("Psalm 1:9223372036854775807") ==
               {"Psalm", "Psa", {1, 9_223_372_036_854_775_807, ""},
                {1, 9_223_372_036_854_775_807, ""}}

      assert error(
               search(%{"query" => "John", "biblical_reference" => "Mark 1:99999999999999999999"})
             ) =~
               "Unsupported biblical_reference"

      assert Ancient.format_biblical_range("Jud", 1, 14, 1, 15) == "Jude 14–15"
      assert Ancient.format_biblical_range("Heb", 9, 1, 10, 999) == "Heb 9–10"
      assert Ancient.format_biblical_range("Gen", 6, 13, 8, 19) == "Gen 6:13–8:19"
    end
  end

  describe "excerpts" do
    test "centre on the first match, through accents, points, signs and prefixes" do
      text =
        String.duplicate("Opening words of the passage. ", 100) <>
          "Herod rebuilt the temple. " <> String.duplicate("Tail. ", 100)

      excerpt = Passages.match_excerpt(text, "temple building", 600)
      assert excerpt =~ "Herod rebuilt the temple."
      assert String.starts_with?(excerpt, "…") and String.ends_with?(excerpt, "…")
      assert String.length(excerpt) <= 602

      greek = String.duplicate("ἀρχή ", 300) <> "τοῦ βαπτιστοῦ" <> String.duplicate(" τέλος", 300)
      assert Passages.match_excerpt(greek, "βαπτιστου", 400) =~ "βαπτιστοῦ"
      assert Passages.match_excerpt("short text", "missing", 600) == "short text"

      filler = String.duplicate("מלה ", 400)
      assert Passages.match_excerpt(filler <> "הַשְּׁקָלִים " <> filler, "שקלים", 600) =~ "הַשְּׁקָלִים"
      assert Passages.match_excerpt(filler <> "אלמנ֯[ו]ת " <> filler, "אלמנות", 600) =~ "אלמנ֯[ו]ת"
      assert Passages.match_excerpt(filler <> "ובהון " <> filler, "הון", 600) =~ "ובהון"
    end

    test "fold strips Greek accents, Hebrew points and cantillation, and folds case" do
      assert Passages.fold("Ἰωάννου ΒΑΠΤΙΣΤΟΥ") == "ιωαννου βαπτιστου"
      assert Passages.fold("בְּרֵאשִׁ֖ית") == "בראשית"
    end

    test "a non-commercial licence is marked and linked" do
      assert Passages.license_text("CC BY-NC-SA 4.0") ==
               "CC BY-NC-SA 4.0 (non-commercial; https://creativecommons.org/licenses/by-nc-sa/4.0/)"

      assert Passages.license_text("CC BY-SA 4.0") == "CC BY-SA 4.0"
    end
  end
end
