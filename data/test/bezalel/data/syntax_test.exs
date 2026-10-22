defmodule Bezalel.Data.SyntaxTest do
  # Not async: Bezalel.Data.Syntax caches its book codes in :persistent_term.
  use ExUnit.Case, async: false

  alias Bezalel.Data.Syntax

  # The core pack's verses.reference forms around the cases below.
  @core [
    ["Psa.3.0(3.1)", "Psa", 3, 0],
    ["Psa.3.1(3.2)", "Psa", 3, 1],
    ["Psa.23.0(23.1)", "Psa", 23, 0],
    ["Psa.23.1", "Psa", 23, 1],
    ["1Sa.20.42", "1Sa", 20, 42],
    ["1Sa.20.42(21.1)", "1Sa", 20, 42],
    ["3Jn.1.15[1.14]", "3Jn", 1, 15],
    ["Jhn.7.53{8.1}", "Jhn", 7, 53],
    ["Phm.1.1", "Phm", 1, 1],
    ["Phm.1.2", "Phm", 1, 2]
  ]

  # A MACULA Hebrew lowfat sentence: the superscription of Psalm 3 (WLC 3:1),
  # with the UBS attributes MACULA marks "Used with permission".
  @psalm """
  <?xml version="1.0" encoding="UTF-8"?>
  <chapter lang="he" id="PSA 3">
    <sentence id="PSA 3:1">
      <p><milestone unit="verse" id="PSA 3:1">PSA 3:1</milestone> מִזְמ֥וֹר לְדָוִ֑ד</p>
      <wg class="cl" rule="S-P">
        <w role="s" ref="PSA 3:1!1" strongnumberx="4210" english="psalm" gloss="psalm" lemma="מִזְמוֹר"
           sdbh="003893001001000" lexdomain="003001" coredomain="102" after=" ">מִזְמ֥וֹר</w>
        <wg role="p" class="pp">
          <w ref="PSA 3:1!2" strongnumberx="3807a" english="of" gloss="to" lemma="לְ">לְ</w>
          <w ref="PSA 3:1!2" strongnumberx="1732" english="David" gloss="David" lemma="דָּוִד" after="׃">דָוִ֑ד</w>
        </wg>
      </wg>
    </sentence>
  </chapter>
  """

  # A MACULA Greek sentence over two verses, with a clause inside a clause
  # and the UBS attributes `ln` and `domain`.
  @philemon """
  <?xml version="1.0" encoding="UTF-8"?>
  <book lang="el" id="PHM">
    <sentence>
      <p><milestone unit="verse" id="PHM 1:1">PHM 1:1</milestone> …</p>
      <wg class="cl" rule="S-V-O">
        <w role="s" ref="PHM 1:1!1" strong="3972" gloss="Paul" english="Paul" lemma="Παῦλος"
           ln="93.294a" domain="093001" after=" ">Παῦλος</w>
        <w role="v" ref="PHM 1:1!2" strong="1125" gloss="writes" lemma="γράφω" after=" ">γράφει</w>
        <wg role="o" class="np">
          <w ref="PHM 1:2!1" strong="3588" gloss="-" english="the" lemma="ὁ" after=" ">τῇ</w>
          <w ref="PHM 1:2!2" strong="1577" gloss="church" lemma="ἐκκλησία" after=",">ἐκκλησίᾳ</w>
          <wg class="cl" Rule="V-O" role="adv">
            <w role="v" ref="PHM 1:2!3" strong="2192" gloss="having" lemma="ἔχω" after=".">ἔχουσα</w>
          </wg>
        </wg>
      </wg>
    </sentence>
  </book>
  """

  defp english, do: Syntax.english_numbering(@core)

  defp rows(xml, language),
    do: xml |> Syntax.parse(language) |> Map.fetch!(:sentences) |> Syntax.rows("f.xml", english())

  describe "english_numbering/1" do
    test "maps the edition's (Hebrew) numbering to the packs' English one, a split verse to both" do
      english = english()

      # The superscription: Hebrew 3:1 is English 3:0, Hebrew 3:2 English 3:1.
      assert english.({"Psa", 3, 1}) == [{3, 0}]
      assert english.({"Psa", 3, 2}) == [{3, 1}]
      # Hebrew 23:1 holds the superscription and English 23:1.
      assert english.({"Psa", 23, 1}) == [{23, 0}, {23, 1}]
      # Two Hebrew verses in one English verse.
      assert english.({"1Sa", 21, 1}) == [{20, 42}]
      assert english.({"1Sa", 20, 42}) == [{20, 42}]
      # STEP's NT brackets and braces are the row's own verse.
      assert english.({"3Jn", 1, 15}) == [{1, 15}]
      assert english.({"Jhn", 7, 53}) == [{7, 53}]
      assert english.({"Psa", 3, 9}) == []
    end
  end

  describe "parse/2 and rows/3" do
    test "a Psalm superscription is filed under verse 0 and names the WLC's verse 1" do
      assert %{rows: [{{"Psa", 3, 0}, view, [{"Psa", 3, 1}], "f.xml"}], unmapped: []} =
               rows(@psalm, "hebrew")

      assert view == %{
               "c" => [
                 [
                   0,
                   nil,
                   "S-P",
                   [
                     ["s", [["מִזְמ֥וֹר ", "H4210", "psalm", "מִזְמוֹר"]]],
                     ["p", [["לְ", nil, "of", "לְ"], ["דָוִ֑ד׃ ", "H1732", "David", "דָּוִד"]]]
                   ]
                 ]
               ],
               "r" => "3:1"
             }
    end

    test "the UBS attributes are counted, never stored" do
      parsed = Syntax.parse(@psalm, "hebrew")
      assert parsed.attribute_counts["sdbh"] == 1
      stored = rows(@psalm, "hebrew").rows |> Enum.map(&elem(&1, 1)) |> JSON.encode!()

      for value <- ["003893001001000", "003001", "102", "93.294a", "093001"],
          do: refute(stored =~ value)

      greek = rows(@philemon, "greek").rows |> Enum.map(&elem(&1, 1)) |> JSON.encode!()
      refute greek =~ "93.294a"
      refute greek =~ "093001"
    end

    test "a sentence across verses: each verse keeps its words, the rest is its text and verse" do
      assert %{rows: [{{"Phm", 1, 1}, first, _, _}, {{"Phm", 1, 2}, second, _, _}], crossing: 1} =
               rows(@philemon, "greek")

      # Verse 1: its own words in full; the object (verse 2) as text with its
      # verse, the clause inside it as a clause in verse 2, counted out.
      assert first == %{
               "c" => [
                 [
                   0,
                   nil,
                   "S-V-O",
                   [
                     ["s", [["Παῦλος ", "G3972", "Paul", "Παῦλος"]]],
                     ["v", [["γράφει ", "G1125", "writes", "γράφω"]]],
                     ["o", [["1:2", "τῇ ἐκκλησίᾳ,"], ["1:2"]]]
                   ]
                 ]
               ],
               "v" => "1:1–2",
               "x" => 1
             }

      # Verse 2: the clause it has words in and the one around it, nested.
      assert %{"c" => [[0, nil, "S-V-O", outer], [1, "adv", "V-O", inner]], "v" => "1:1–2"} =
               second

      assert outer == [
               ["s", [["1:1", "Παῦλος"]]],
               ["v", [["1:1", "γράφει"]]],
               [
                 "o",
                 [["τῇ ", "G3588", "-", "ὁ"], ["ἐκκλησίᾳ, ", "G1577", "church", "ἐκκλησία"], 2]
               ]
             ]

      assert inner == [["v", [["ἔχουσα. ", "G2192", "having", "ἔχω"]]]]
    end

    test "a verse the core pack lacks is reported, not filed" do
      assert %{rows: [], unmapped: [{"Psa", 3, 1}]} =
               @psalm
               |> Syntax.parse("hebrew")
               |> Map.fetch!(:sentences)
               |> Syntax.rows("f.xml", Syntax.english_numbering([]))
    end

    test "an element MACULA's lowfat files don't have stops the build" do
      xml =
        String.replace(@psalm, "<wg role=\"p\" class=\"pp\">", "<wg role=\"p\" class=\"pp\"><x/>")

      assert_raise ArgumentError, ~r/unknown element <x>/, fn -> Syntax.parse(xml, "hebrew") end
    end
  end

  # Gen 1:4 (an object clause directly in its clause), Gen 2:4 (two sibling
  # prepositional phrases, PP-PP) and John 1:3 (a relative clause inside
  # the subject), shortened.
  @structures """
  <?xml version="1.0" encoding="UTF-8"?>
  <chapter lang="he" id="GEN 1">
    <sentence>
      <wg class="cl" rule="V-S-O">
        <w role="v" ref="GEN 1:4!1" strongnumberx="7200" english="saw" gloss="he.saw" lemma="רָאָה" after=" ">וַיַּ֧רְא</w>
        <w role="s" ref="GEN 1:4!2" strongnumberx="0430" english="God" lemma="אֱלֹהִים" after=" ">אֱלֹהִ֛ים</w>
        <wg role="o" class="cl" rule="O-P">
          <w role="o" ref="GEN 1:4!3" strongnumberx="0216" english="light" lemma="אוֹר" after=" ">הָא֖וֹר</w>
          <w role="p" ref="GEN 1:4!4" strongnumberx="2896" english="good" lemma="טוֹב" after="׃">ט֑וֹב</w>
        </wg>
      </wg>
    </sentence>
    <sentence>
      <wg class="cl" rule="S-PP-PP">
        <w role="s" ref="GEN 2:4!1" strongnumberx="0428" english="these" lemma="אֵלֶּה" after=" ">אֵ֣לֶּה</w>
        <wg role="pp" class="pp"><w ref="GEN 2:4!2" strongnumberx="0871a" english="when" lemma="בְּ" after=" ">בְּהִבָּרְאָ֑ם</w></wg>
        <wg role="pp" class="pp"><w ref="GEN 2:4!3" strongnumberx="3117" english="in day" lemma="יוֹם" after=" ">בְּי֗וֹם</w></wg>
      </wg>
    </sentence>
    <sentence>
      <wg class="cl" rule="S-V">
        <w role="v" ref="GEN 2:5!1" strongnumberx="1961" english="was" lemma="הָיָה" after=" ">היה</w>
        <wg role="s" class="np" rule="NP-CL">
          <w ref="GEN 2:5!2" strongnumberx="3605" english="all" lemma="כֹּל" after=" ">כל</w>
          <wg class="cl" rule="V"><w role="v" ref="GEN 2:5!3" strongnumberx="6213" english="made" lemma="עָשָׂה" after="׃">עשה</w></wg>
        </wg>
      </wg>
    </sentence>
  </chapter>
  """

  defp clauses_of(xml),
    do:
      xml
      |> Syntax.parse("hebrew")
      |> Map.fetch!(:sentences)
      |> Enum.map(&elem(Syntax.clauses(&1), 0))

  describe "clauses/1" do
    test "an inner clause with a role of its own is filed under that role in its parent" do
      [[outer, inner] | _] = clauses_of(@structures)
      assert [{"v", _}, {"s", _}, {"o", [{:c, id}]}] = outer.parts
      assert inner.id == id and inner.role == "o"
    end

    test "sibling constituents with the same role stay separate parts" do
      [_, [clause] | _] = clauses_of(@structures)
      assert [{"s", _}, {"pp", [_]}, {"pp", [_]}] = clause.parts
    end

    test "a clause inside a constituent has no role of its own, only its place" do
      [_, _, [outer, inner]] = clauses_of(@structures)
      assert [{"v", _}, {"s", [{:w, _}, {:c, id}]}] = outer.parts
      assert inner.id == id and inner.role == nil
    end

    test "the Hebrew gloss (SIL's SILHA) is never read; Cherith's english or nothing" do
      [[outer | _] | _] = clauses_of(@structures)
      [{"v", [{:w, saw}]} | _] = outer.parts
      assert saw.gloss == "saw"

      without = String.replace(@structures, ~s(english="saw" ), "")
      [[outer | _] | _] = clauses_of(without)
      [{"v", [{:w, saw}]} | _] = outer.parts
      assert saw.gloss == nil
      refute without |> Syntax.parse("hebrew") |> Map.fetch!(:sentences) |> inspect() =~ "he.saw"
    end
  end

  test "strong/2 writes Bezalel's form, dropping MACULA's own letter suffixes" do
    assert Syntax.strong("0430", "H") == "H0430"
    # A suffixed number is another word (0871a בְּ; H0871 is Atharim).
    assert Syntax.strong("0871a", "H") == nil
    assert Syntax.strong("2050b", "H") == nil
    assert Syntax.strong("976", "G") == "G0976"
    assert Syntax.strong(nil, "G") == nil
  end
end
