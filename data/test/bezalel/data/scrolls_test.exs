defmodule Bezalel.Data.ScrollsTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.Scrolls
  alias Bezalel.Study.Ancient

  # Signs as Text-Fabric gives them: a map per feature, by slot.
  defp signs(list) do
    features = ~w(type glyph after unc rec rem cor alt vac lang)
    empty = Map.new(features, &{&1, %{}})

    list
    |> Enum.with_index(1)
    |> Enum.reduce(empty, fn {sign, slot}, signs ->
      Enum.reduce(sign, signs, fn {feature, value}, signs ->
        put_in(signs, [to_string(feature), slot], value)
      end)
    end)
  end

  defp letter(glyph, more \\ []), do: [type: "cons", glyph: glyph] ++ more

  describe "render/2" do
    test "brackets reconstruction and corrections, marks uncertain letters, drops the morpheme break" do
      signs =
        signs([
          letter("ב"),
          [type: "sep", glyph: "׳"],
          letter("ית", after: " "),
          letter("א", unc: "2"),
          letter("ל", rec: "1"),
          letter("ה", rec: "1", after: " "),
          letter("ו", cor: "3"),
          letter("ם", after: " "),
          [type: "empty", vac: "1"],
          [type: "missing", glyph: "ε", after: " "],
          [type: "unc", glyph: "ε"],
          [type: "punct", glyph: "׃"]
        ])

      assert Scrolls.render(1..12, signs) == "בית א\u05AF[לה] ^ו^ם vacat … ◦׃"
    end

    test "an empty pair of brackets keeps a space inside; an unknown sign type stops" do
      signs = signs([letter("א", after: " "), [type: "empty", rec: "1"], letter("ב")])
      assert Scrolls.render(1..3, signs) == "א [ ]ב"

      assert_raise ArgumentError, ~r/unknown ETCBC sign type "glyphish" at slot 1/, fn ->
        Scrolls.render(1..1, signs([[type: "glyphish", glyph: "x"]]))
      end
    end

    test "the Copper Scroll's Greek letters are text" do
      assert Scrolls.render(1..2, signs([letter("א"), [type: "foreign", glyph: "Κ"]])) == "אΚ"
    end
  end

  test "letters/2 and language/2 count letters only, reconstruction and Aramaic by sign" do
    signs =
      signs([
        letter("א", lang: "a"),
        letter("ב", rec: "1", lang: "a"),
        [type: "punct", glyph: "׃"],
        letter("ג")
      ])

    assert Scrolls.letters(1..4, signs) == {3, 2}
    assert Scrolls.language(1..4, signs) == "Aramaic"
    assert Scrolls.language(3..4, signs) == "Hebrew"
  end

  describe "search text (the ancient pack's Qumran rules)" do
    test "reconstruction is a word break, removals and vacat are deleted, marks folded" do
      words =
        "1 [המשא] ש֯ועתי ולוא vacat יג[די]לו י{{א}}<<ע>>בורו"
        |> Scrolls.index_text()
        |> String.split()

      assert words == ["1", "שועתי", "ולוא", "יג", "לו", "יעבורו"]
    end

    test "prefix variants keep three letters and skip words the passage has" do
      assert Scrolls.prefix_variants("ובהון בהון בית [ומקדש]") == "הון"
      assert Scrolls.prefix_variants("ומקדש") == "מקדש קדש"
    end
  end

  test "labels: a column stays a number, a fragment becomes 'frg.' and reads back as one key" do
    for {etcbc, shown} <- [
          {"5", "5"},
          {"f1_2i", "frg. 1–2 i"},
          {"f1_3ii", "frg. 1–3 ii"},
          {"f1aii", "frg. 1a ii"},
          {"f7a", "frg. 7a"},
          {"fA1", "frg. A1"},
          {"f2i+3", "frg. 2 i + 3"}
        ] do
      assert Scrolls.display_label(etcbc) == shown
      key = Ancient.fragment_key(etcbc)
      assert Ancient.fragment_key(shown) == key, etcbc
    end

    assert Scrolls.span("5", "3", "9") == "5:3–9"
    assert Scrolls.span("f1_2i", "4", "4") == "frg. 1–2 i 4"
  end

  test "sites by siglum; book acronyms; an unknown siglum stops" do
    assert Scrolls.site("4Q37") == "Qumran Cave 4"
    assert Scrolls.site("Mas1a") == "Masada"
    assert Scrolls.site("5/6hev1b") == "Nahal Hever (Cave 5/6)"
    assert_raise ArgumentError, fn -> Scrolls.site("Zzz1") end

    assert Scrolls.book("Deut") == "Deu"
    assert Scrolls.book("Is") == "Isa"
    assert Scrolls.book("4Q1") == nil
  end

  test "english_numbering/1 maps ETCBC's Hebrew numbers through the core pack's references" do
    english =
      Scrolls.english_numbering(["Psa.3.0(3.1)", "Psa.3.1(3.2)", "Gen.1.1", "Mal.4.1(3.19)"])

    assert english.({"Psa", 3, 1}) == {3, 0}
    assert english.({"Psa", 3, 2}) == {3, 1}
    assert english.({"Mal", 3, 19}) == {4, 1}
    assert english.({"Gen", 1, 1}) == {1, 1}
    # Psa.3.0 exists only as English numbering; Gen 9:9 not at all.
    assert english.({"Psa", 3, 0}) == nil
    assert english.({"Gen", 9, 9}) == nil
  end

  # A biblical scroll 4Q1 with two lines of fragment 1 and a non-biblical
  # scroll 4Q999 with fragment 1–2 i (two lines) and fragment 3 (one line).
  defp data do
    signs =
      signs([
        # 4Q1 line 1: slots 1–5
        letter("א", after: " "),
        letter("ב", after: " "),
        letter("ג", after: " "),
        letter("ד"),
        letter("ה", after: " "),
        # 4Q1 line 2: slots 6–9
        letter("ו", after: " "),
        letter("ז", after: " "),
        letter("ח", rec: "1"),
        letter("ט", rec: "1"),
        # 4Q999 frg. 1–2 i line 1, line 2; frg. 3 line 1: slots 10–12
        letter("כ", lang: "a"),
        letter("ל", lang: "a"),
        letter("מ")
      ])

    biblical = %{node: 100, siglum: "4Q1", biblical: true, slots: 1..9}
    other = %{node: 101, siglum: "4Q999", biblical: false, slots: 10..12}

    lines = [
      %{node: 50, siglum: "4Q1", fragment: "f1", line: "1", slots: 1..5},
      %{node: 51, siglum: "4Q1", fragment: "f1", line: "2", slots: 6..9},
      %{node: 52, siglum: "4Q999", fragment: "f1_2i", line: "1", slots: 10..10},
      %{node: 53, siglum: "4Q999", fragment: "f1_2i", line: "2", slots: 11..11},
      %{node: 54, siglum: "4Q999", fragment: "f3", line: "1", slots: 12..12}
    ]

    words = [
      %{node: 200, book: "Gen", chapter: "1", verse: "1", slots: 1..2},
      %{node: 201, book: "4Q1", chapter: "f1", verse: "1", slots: 3..3},
      %{node: 202, book: "Gen", chapter: "1", verse: "2", slots: 4..5},
      %{node: 203, book: "Gen", chapter: "1", verse: "2", slots: 6..7},
      %{node: 204, book: "Gen", chapter: "1", verse: "1", slots: 8..9}
    ]

    %{
      scrolls: %{
        lines: %{50 => biblical, 51 => biblical, 52 => other, 53 => other, 54 => other},
        nodes: [biblical, other]
      },
      lines: lines,
      words: words,
      signs: signs
    }
  end

  test "biblical/3: a row per manuscript and verse, lines joined, unidentified words left out" do
    result =
      Scrolls.biblical(data(), fn {_book, chapter, verse} -> {chapter, verse} end, %{
        "4Q1" => "4QGen-Exoda"
      })

    assert [first, again, second] = result.verses

    assert %{
             reference: "Gen.1.1",
             occurrence: 1,
             locator: "frg. 1 1",
             text: "א ב",
             letters: 2,
             preserved_letters: 2
           } = first

    assert %{reference: "Gen.1.1", occurrence: 2, text: "[חט]", letters: 2, preserved_letters: 0} =
             again

    assert %{
             reference: "Gen.1.2",
             locator: "frg. 1 1–2",
             text: "דה / ו ז",
             name: "4QGen-Exoda",
             mt_verse: 1
           } = second

    assert result.unidentified == [{"4Q1", 1}]

    assert [
             %{
               siglum: "4Q1",
               books: "Gen",
               verses: 3,
               reconstructed_only: 1,
               site: "Qumran Cave 4"
             }
           ] = result.manuscripts

    assert result.unmapped == []
  end

  test "biblical/3 keeps a verse the core pack lacks under ETCBC's numbering" do
    result = Scrolls.biblical(data(), fn _ -> nil end, %{})
    assert Enum.all?(result.verses, &(&1.mt_verse == 0))
    assert "Gen.1.2" in result.unmapped
  end

  test "passages/3: one passage per label, lines numbered, cited by label and conventional name" do
    work = %{
      siglum: "4Q999",
      key: "dss_4q999",
      composition: "Test Work",
      title: "Test Work (4QTest)",
      reference_title: "4Q999",
      name: "4QTest",
      periods: "second_temple"
    }

    provenance = %{edition: "ed", license: "CC BY-NC 4.0", source_url: "url"}
    assert {[one, two], []} = Scrolls.passages(data(), [work], provenance)

    assert %{
             reference: "4Q999 frg. 1–2 i 1–2",
             alternate_reference: "4QTest frg. 1–2 i 1–2",
             author: "Test Work",
             section_number: "f1-2i",
             book_number: 1,
             sort_start: 1001,
             sort_end: 1002,
             original_text: "1 כ\n2 ל",
             original_language: "Aramaic"
           } = one

    assert %{reference: "4Q999 frg. 3 1", sort_start: 2001, original_language: "Hebrew"} = two

    bad = %{data() | lines: Enum.map(data().lines, &%{&1 | line: "1a"})}

    assert_raise RuntimeError, ~r/line label "1a" is not a number/, fn ->
      Scrolls.passages(bad, [work], provenance)
    end
  end
end
