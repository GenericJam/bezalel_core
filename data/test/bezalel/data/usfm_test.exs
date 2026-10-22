defmodule Bezalel.Data.UsfmTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.{Door43, Jps, Usfm}

  doctest Door43

  # Tit 1:1 as Door43's ULT writes it: every word aligned to the Greek.
  @aligned """
  \\id TIT EN_ULT en_English_ltr tc
  \\usfm 3.0
  \\h Titus
  \\toc1 The Letter of Paul to Titus
  \\mt1 Titus

  \\ts\\*
  \\c 1
  \\p
  \\v 1 \\zaln-s |x-strong="G39720" x-lemma="Παῦλος" x-content="Παῦλος"\\*\\w Paul|x-occurrence="1" x-occurrences="1"\\w*\\zaln-e\\*,
  \\zaln-s |x-strong="G14010" x-content="δοῦλος"\\*\\w a|x-occurrence="1" x-occurrences="1"\\w*
  \\w servant|x-occurrence="1" x-occurrences="1"\\w*\\zaln-e\\* {\\w of|x-occurrence="1"\\w*} \\w God|x-occurrence="1"\\w*’\\w s|x-occurrence="1"\\w*
  \\f + \\ft A footnote. \\fqa servant \\fqa*\\f*
  \\v 2 \\w Grace|x-occurrence="1"\\w*.
  """

  defp book(usfm, code \\ "TIT", book \\ "Tit"), do: Usfm.book(usfm, code, book)

  test "keeps the words of aligned text and drops the alignment, attributes, milestones and footnotes" do
    assert %{rows: [one, two], footnotes: [{"Tit.1.1", "+ A footnote. servant"}]} = book(@aligned)

    assert one == %{
             reference: "Tit.1.1",
             book: "Tit",
             chapter: 1,
             verse: 1,
             text: "Paul, a servant {of} God’s"
           }

    assert two.text == "Grace."
  end

  test "a Psalm title (\\d, before or at the start of verse 1) is verse 0; Selah and the book heading" do
    usfm = """
    \\id PSA
    \\c 3
    \\ms1 Book One
    \\d A psalm of David
    \\q1 \\v 1 Yahweh, how many!
    \\qs Selah\\qs*
    \\c 4
    \\q1 \\v 1 \\d For the chief musician
    \\q1 Answer me.
    """

    assert %{rows: rows, headings: [{"Psa.3", "ms1", "Book One"}]} = book(usfm, "PSA", "Psa")

    assert Enum.map(rows, &{&1.reference, &1.text}) == [
             {"Psa.3.0", "A psalm of David"},
             {"Psa.3.1", "Yahweh, how many! Selah"},
             {"Psa.4.0", "For the chief musician"},
             {"Psa.4.1", "Answer me."}
           ]
  end

  test "drops section headings by their markers and keeps a verse bridge on its first verse" do
    usfm = """
    \\id EXO
    \\c 33
    \\s1 The people mourn
    \\sr 33:1-6
    \\p
    \\v 4-5 When the people heard this, they mourned.
    \\v 6 So they stripped themselves.
    """

    assert %{rows: rows, bridges: [{"Exo.33.4", "4-5"}], headings: headings} =
             book(usfm, "EXO", "Exo")

    assert Enum.map(rows, & &1.reference) == ["Exo.33.4", "Exo.33.6"]
    assert Enum.map(headings, &elem(&1, 1)) == ["s1", "sr"]
  end

  test "refuses what it doesn't know: a marker, text outside a verse, a title outside a Psalm" do
    assert_raise ArgumentError, ~r/unexpected marker \\add/, fn ->
      book("\\id TIT\n\\c 1\n\\p\n\\v 1 \\add Paul\\add*\n")
    end

    assert_raise ArgumentError, ~r/text outside a verse/, fn ->
      book("\\id TIT\n\\c 1\n\\p Paul\n")
    end

    assert_raise ArgumentError, ~r/a superscription outside a Psalm's first verse/, fn ->
      book("\\id HAB\n\\c 3\n\\d A prayer\n", "HAB", "Hab")
    end

    assert_raise ArgumentError, ~r/isn't TIT/, fn -> book("\\id PHM\n") end
  end

  describe "Jps.hebrew_numbers/2" do
    # The core pack's numbering: Psalm 3's title is Hebrew 3:1 (English 3:0);
    # Hebrew 51:1-2 are English 51:0; Mal 3:19 is English 4:1.
    @english %{
      {"Psa", 3, 1} => {3, 0},
      {"Psa", 3, 2} => {3, 1},
      {"Psa", 51, 1} => {51, 0},
      {"Psa", 51, 2} => {51, 0},
      {"Psa", 51, 3} => {51, 1},
      {"Psa", 81, 1} => {81, 0},
      {"Psa", 81, 2} => {81, 1},
      {"Mal", 3, 19} => {4, 1},
      {"Exo", 20, 13} => {20, 13}
    }

    defp numbered(rows), do: Jps.hebrew_numbers(rows, &Map.get(@english, &1))

    defp row(reference, text) do
      [book, chapter, verse] = String.split(reference, ".")

      %{
        reference: reference,
        book: book,
        chapter: String.to_integer(chapter),
        verse: String.to_integer(verse),
        text: text
      }
    end

    test "moves a Psalm title to verse 0 by its Hebrew numbers and removes them" do
      result =
        numbered([
          row("Psa.3.1", "(3-1) A Psalm of David. (3-2) LORD, how many!"),
          row("Psa.51.1", "(51-1) For the Leader; (51-2) when Nathan came. (51-3) Be gracious"),
          row("Psa.81.1", "For the Leader. (81-2) Sing aloud")
        ])

      assert Enum.map(result.rows, &{&1.reference, &1.text}) == [
               {"Psa.3.0", "A Psalm of David."},
               {"Psa.3.1", "LORD, how many!"},
               {"Psa.51.0", "For the Leader; when Nathan came."},
               {"Psa.51.1", "Be gracious"},
               {"Psa.81.0", "For the Leader."},
               {"Psa.81.1", "Sing aloud"}
             ]

      assert result.numbers == 6
      assert result.titles == ["Psa.3.0", "Psa.51.0", "Psa.81.0"]
    end

    test "keeps eBible's English verse where the core numbers the Hebrew verse elsewhere" do
      result =
        numbered([
          row("Mal.4.1", "(3-19) For, behold, the day cometh"),
          row("Exo.20.14", "(20-13) Thou shalt not commit adultery.")
        ])

      assert Enum.map(result.rows, &{&1.reference, &1.text}) == [
               {"Mal.4.1", "For, behold, the day cometh"},
               {"Exo.20.14", "Thou shalt not commit adultery."}
             ]

      assert result.elsewhere == [{"Exo.20.14", "(20-13)"}]
    end
  end

  describe "Door43" do
    test "the adaptation's row drops the trademark and keeps the attribution its licence asks" do
      ult = Door43.translation("ult")
      assert ult.key == "ult"
      refute ult.name =~ "unfoldingWord"

      assert ult.copyright =~
               "The original work by unfoldingWord is available from unfoldingword.org/ult."

      assert Door43.translation("ust").abbreviation == "UST"
    end

    test "checks the release's licence still has the terms followed" do
      licence =
        "*unfoldingWord® Literal Text* … Creative Commons Attribution-ShareAlike 4.0 " <>
          "International License … you must remove the unfoldingWord® trademark … " <>
          "“The original work by unfoldingWord is available from [unfoldingword.org/ult](…)”"

      assert Door43.check_licence!("ult", licence) == :ok

      assert_raise ArgumentError, ~r/lacks/, fn ->
        Door43.check_licence!("ult", String.replace(licence, "ShareAlike", "NonCommercial"))
      end
    end

    test "reads the book files of a release, not its front matter" do
      assert Door43.book_file?("57-TIT.usfm")
      refute Door43.book_file?("A0-FRT.usfm")
      refute Door43.book_file?("LICENSE.md")

      assert %{books: ["Tit"], rows: [%{reference: "Tit.1.1"} | _]} =
               Door43.rows(%{"57-TIT.usfm" => @aligned, "LICENSE.md" => "", "A0-FRT.usfm" => ""})
    end
  end
end
