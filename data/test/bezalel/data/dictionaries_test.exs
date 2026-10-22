defmodule Bezalel.Data.DictionariesTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.Dictionaries

  [hebrew, greek] = Dictionaries.dictionaries()
  @hebrew hebrew
  @greek greek

  # Hebrew Job 41:8 is English Job 41:16; Php 1:17 and Lev 11:1 as they are.
  defp english({"Job", 41, 8}), do: {41, 16}
  defp english({"Php", 1, 17}), do: {1, 17}
  defp english({"Lev", 11, 1}), do: {11, 1}
  defp english(_verse), do: nil

  defp clean(text, kind \\ :definition), do: Dictionaries.clean(text, kind, &english/1)

  describe "normalize_strongs/2" do
    test "Aramaic codes are the core lexicon's H numbers; letters and missing prefixes are dropped" do
      assert Dictionaries.normalize_strongs("A0004", "H") == "H0004"
      assert Dictionaries.normalize_strongs("H0032b", "H") == "H0032"
      assert Dictionaries.normalize_strongs("A2452", "H") == "H2452"
      assert Dictionaries.normalize_strongs("2062", "H") == "H2062"
      assert Dictionaries.normalize_strongs("G0518a", "G") == "G0518"
      assert Dictionaries.normalize_strongs("G0026", "G") == "G0026"
    end

    test "a compound name's code and an empty one key nothing; anything else stops the build" do
      assert Dictionaries.normalize_strongs("H0410+H1285", "H") == nil
      assert Dictionaries.normalize_strongs("", "H") == nil
      assert_raise ArgumentError, fn -> Dictionaries.normalize_strongs("X12", "H") end
    end
  end

  describe "clean/3" do
    test "links, Louw–Nida numbers, abbreviations, footnotes and italics" do
      assert clean("king {L:Ahasuerus<SDBH:אֲחַשְׁוֵרֹושׁ>} of {L:moth<BT-OT:עָשׁ>}") ==
               {"king Ahasuerus of moth", %{"link" => 2}}

      assert clean("see {D:25.43} and {D:93.294a}{N:001}") ==
               {"see LN 25.43 and LN 93.294a", %{"louw_nida" => 2, "footnote" => 1}}

      assert clean("according to {A:NIV}; ◄ |iCanis familiaris|i*") ==
               {"according to NIV; ◄ Canis familiaris", %{"abbreviation" => 1, "italics" => 1}}

      assert {"as σπυρίς (LN 6.149).", %{"louw_nida_unclosed" => 1}} =
               clean("as σπυρίς ({D:6.149).", :comments)
    end

    test "Scripture references in the packs' English numbering: lists, ranges, chapters" do
      assert {"a breeze (Job.41.16)", %{"scripture" => 1}} =
               clean("a breeze ({S:01804100800000})")

      assert {"in Php.1.17, Job.41.16", _} =
               clean("in {S:05000101700012 05000101700020 01804100800000 }")

      assert {"see Php.1.17–Job.41.16", _} = clean("see {S:05000101700000-01804100800000}")
      assert {"in Lev.11", _} = clean("in {S:00301100000000}")

      assert_raise ArgumentError, ~r/no Gen 1:1/, fn -> clean("{S:00100100100000}") end
    end

    test "a pipe is a paragraph break in comments only; unknown markup stops the build" do
      assert {"one two", %{"paragraph" => 1}} = clean("one|two", :comments)
      assert_raise ArgumentError, fn -> clean("one|two") end
      assert_raise ArgumentError, fn -> clean("{X:1}") end
      assert_raise ArgumentError, fn -> clean("{L:a<SDBH:b>") end
      # Plain angle brackets are text.
      assert {"father > founder", %{}} = clean("father > founder")
    end
  end

  describe "english_numbering/2" do
    # As the core pack writes them: English numbering, Hebrew in ( ), the NT's
    # alternatives in [ ].
    @core ~w"Psa.69.24(69.25) Psa.69.25(69.26) Dan.6.21(6.22) Dan.6.22(6.23) Php.1.16[1.17]
             Php.1.17[1.16] Jhn.3.16"

    test "the Hebrew dictionary's references are mapped from the Hebrew numbering" do
      english = Dictionaries.english_numbering(@core, :hebrew)
      assert english.({"Psa", 69, 26}) == {69, 25}
      assert english.({"Dan", 6, 23}) == {6, 22}
      assert english.({"Php", 1, 17}) == {1, 17}
    end

    test "the Greek dictionary's, OT quotations too, are English already, checked against the core" do
      english = Dictionaries.english_numbering(@core, :english)
      # Acts 1:20 quotes Ps 69:25; Heb 11:33 alludes to Dan 6:22.
      assert english.({"Psa", 69, 25}) == {69, 25}
      assert english.({"Dan", 6, 22}) == {6, 22}
      assert english.({"Php", 1, 17}) == {1, 17}
      assert english.({"Jhn", 3, 16}) == {3, 16}
      assert english.({"Jhn", 3, 99}) == nil

      assert {"a quotation of Psa.69.25", _} =
               Dictionaries.clean("a quotation of {S:01906902500000}", :comments, english)
    end
  end

  describe "load/4" do
    @domains %{
      "001" => %{name: "Objects", level: 1},
      "001001001" => %{name: "Deities", level: 3},
      "001001004" => %{name: "Spirits", level: 3}
    }

    defp sense(fields),
      do:
        Map.merge(
          %{
            "LanguageCode" => "en",
            "DefinitionShort" => "= a being",
            "Glosses" => ["spirit"],
            "Comments" => ""
          },
          fields
        )

    defp meaning(id, domains, senses, refs \\ ["02200601100016"]) do
      %{
        "LEXID" => id,
        "LEXEntryCode" => "",
        "LEXDomains" => domains,
        "LEXSubDomains" => nil,
        "LEXSenses" => senses,
        "LEXReferences" => refs
      }
    end

    defp domain(code, name, source_code \\ "", source \\ ""),
      do: %{
        "DomainCode" => code,
        "Domain" => name,
        "DomainSourceCode" => source_code,
        "DomainSource" => source
      }

    test "entries keyed by Strong's, meanings with domains; slips left out and counted" do
      json =
        Jason.encode!([
          %{
            "MainId" => "000001000000000",
            "Lemma" => "רוּחַ",
            "StrongCodes" => ["H7307", "A7308"],
            "BaseForms" => [
              %{
                "PartsOfSpeech" => ["noun f"],
                "LEXMeanings" => [
                  meaning("000001001001000", [domain("001001001", "Deities")], [sense(%{})]),
                  meaning(
                    "000001001002000",
                    [domain("001001004", "Spirits", "001001001", "Deities")],
                    [sense(%{"AIGenerated" => true}), sense(%{"Glosses" => ["ghost"]})],
                    nil
                  ),
                  # The contextual label on a lexical code: left out.
                  meaning("000001001003000", [domain("001", "Ability")], [sense(%{})])
                ]
              }
            ]
          },
          %{
            "MainId" => "000002000000000",
            "Lemma" => "אֵל בְּרִית",
            "StrongCodes" => ["H0410+H1285"],
            "BaseForms" => []
          }
        ])

      data = Dictionaries.load(json, @domains, @hebrew, &english/1)

      assert [
               %{entry_id: "000001000000000", lemma: "רוּחַ", strong_codes: "H7307 A7308"},
               %{entry_id: "000002000000000", strong_codes: "H0410+H1285"}
             ] = data.entries

      assert Enum.map(data.strongs, &{&1.strongs, &1.given}) == [
               {"H7307", "H7307"},
               {"H7308", "A7308"}
             ]

      assert [
               %{
                 position: 1,
                 part_of_speech: "noun f",
                 glosses: ~S(["spirit"]),
                 reference_count: 1
               },
               %{position: 2, glosses: ~S(["ghost"]), reference_count: 0},
               %{position: 3}
             ] = data.meanings

      assert Enum.map(data.meaning_domains, &{&1.meaning_id, &1.code, &1.source_code}) == [
               {"000001001001000", "001001001", nil},
               {"000001001002000", "001001004", "001001001"}
             ]

      assert data.stats.ai_generated == 1
      assert data.stats.references == 2
      assert data.stats.no_strongs == ["אֵל בְּרִית (H0410+H1285)"]
      assert [{"000001001003000", "001", "Ability", "Objects"}] = data.stats.dropped_domains
    end

    test "a Hebrew dictionary refuses a Greek code" do
      json =
        Jason.encode!([
          %{"MainId" => "1", "Lemma" => "x", "StrongCodes" => ["G0026"], "BaseForms" => []}
        ])

      assert_raise RuntimeError, fn -> Dictionaries.load(json, @domains, @hebrew, &english/1) end
      assert %{entries: [_]} = Dictionaries.load(json, @domains, @greek, &english/1)
    end
  end

  test "the README must still grant CC BY-SA 4.0 with the attribution recorded" do
    readme =
      "This work is licensed under a\n[Creative Commons Attribution-ShareAlike 4.0 International License][cc-by-sa].\n" <>
        "(UBS Dictionary of Biblical Hebrew © United Bible Societies, 2023.  Adapted from Semantic " <>
        "Dictionary of Biblical Hebrew © 2000-2023 United Bible Societies.)"

    assert Dictionaries.check_licence(readme, @hebrew) == :ok

    assert {:error, _} =
             Dictionaries.check_licence(
               String.replace(readme, "ShareAlike", "NonCommercial"),
               @hebrew
             )

    assert {:error, _} =
             Dictionaries.check_licence(String.replace(readme, "2023.", "2026."), @hebrew)
  end
end
