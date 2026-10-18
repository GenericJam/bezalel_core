defmodule Bezalel.Data.NetTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.Net

  doctest Net

  describe "parse/2" do
    test "keeps the words of Strong's-tagged text and drops note markers" do
      html =
        ~S(The <st data-num="01121" class="">people</st><n id="1" /> to whom ) <>
          ~S(<st data-num="0589" class="">I</st> am sending you.)

      assert Net.parse(html).text == "The people to whom I am sending you."
    end

    test "writes small capitals in capitals: LORD for the divine name, Lord otherwise" do
      html =
        ~S(<p class="poetry">The <span class="smcaps"><st data-num="03068">Lord</st></span>) <>
          ~S( is my shepherd; my <st data-num="0136">Lord</st> and my God)

      assert Net.parse(html).text == "The LORD is my shepherd; my Lord and my God"
    end

    test "reads a class with doubled quotes, as the service sometimes sends" do
      assert Net.parse(~S(the <span class=""smcaps"">Lord</span> stood)).text == "the LORD stood"
    end

    test "splits a Psalm superscription off verse 1" do
      html =
        ~S(<p class="psasuper">A <st data-num="04210">psalm</st> of David.<n id="1" /> ) <>
          ~S(<p class="poetry"><span class="smcaps">Lord</span>, how numerous are my enemies!) <>
          ~S(<p class="poetry">Many attack me.</p>)

      assert %{
               superscription: "A psalm of David.",
               text: "LORD, how numerous are my enemies! Many attack me.",
               headings: []
             } = Net.parse(html)
    end

    test "drops headings: Song of Songs speakers, acrostic letters, section titles" do
      speaker =
        ~S(chambers!<n id="6" /> <p class="sosspeaker"><b><i>The Maidens</i></b><n id="7" /> ) <>
          ~S(<b><i>to the Lover:</i></b><p class="poetry">We will rejoice)

      assert %{
               text: "chambers! We will rejoice",
               headings: [{"sosspeaker", "The Maidens to the Lover:"}]
             } =
               Net.parse(speaker)

      acrostic =
        ~S|<p class="lamhebrew"><span class="hebrew">א</span> (<i>Alef</i>)<n id="1" />| <>
          ~S(<p class="poetry">How blessed)

      assert %{text: "How blessed", headings: [{"lamhebrew", "א (Alef)"}]} = Net.parse(acrostic)

      title = ~S(Israel.<p class="paragraphtitle">The Ark Is Lost<p class="bodytext">Then the)

      assert %{text: "Israel. Then the", headings: [{"paragraphtitle", "The Ark Is Lost"}]} =
               Net.parse(title)
    end

    test "a paragraph or line break separates words" do
      html =
        ~S(in the land of Judah,<p class="otpoetry"><b>are in no way least</b><br></p>) <>
          ~S(and so on)

      assert Net.parse(html).text == "in the land of Judah, are in no way least and so on"
    end

    test "keeps punctuation and quotation marks as given, collapsing whitespace only" do
      html = "  He said,  “Let’s go – now!”\n (Selah) <sup></sup> "
      assert Net.parse(html).text == "He said, “Let’s go – now!” (Selah)"
    end

    test "decodes character entities" do
      assert Net.parse("salt &amp; light &#8212; &quot;yes&quot;").text ==
               "salt & light — \"yes\""
    end

    test "refuses markup it doesn't know" do
      assert_raise ArgumentError, ~r/unexpected markup <table>/, fn -> Net.parse("<table>x") end

      assert_raise ArgumentError, ~r/unexpected paragraph/, fn ->
        Net.parse(~S(<p class="footnote">x))
      end

      assert_raise ArgumentError, ~r/unexpected <span/, fn ->
        Net.parse(~S(<span class="red">x</span>))
      end

      assert_raise ArgumentError, ~r/unclosed/, fn -> Net.parse("<st>word") end
      assert_raise ArgumentError, ~r/closes/, fn -> Net.parse("<i>word</b>") end
      assert_raise ArgumentError, ~r/unknown entity/, fn -> Net.parse("&nbsp;") end
    end
  end

  describe "book_rows/2" do
    @psalms {"Psa", "Psalms", 150}

    test "a superscription becomes verse 0 before verse 1, in STEP references" do
      items = [
        %{
          "chapter" => "3",
          "verse" => "1",
          "text" => ~S(<p class="psasuper">By David.<p class="poetry">Rise up!)
        },
        %{"chapter" => "3", "verse" => "2", "text" => "Many say."}
      ]

      assert %{rows: rows, empty: [], headings: []} = Net.book_rows(@psalms, items)

      assert [
               %{reference: "Psa.3.0", book: "Psa", chapter: 3, verse: 0, text: "By David."},
               %{reference: "Psa.3.1", verse: 1, text: "Rise up!"},
               %{reference: "Psa.3.2", verse: 2, text: "Many say."}
             ] = rows
    end

    test "a verse the source gives without text is reported, not stored" do
      items = [%{"chapter" => "24", "verse" => "7", "text" => ""}]
      assert %{rows: [], empty: ["Act.24.7"]} = Net.book_rows({"Act", "Acts", 28}, items)
    end

    test "refuses a superscription outside a Psalm's first verse, and verses outside the book" do
      superscription = ~S(<p class="psasuper">By David.)

      assert_raise ArgumentError, ~r/Psa.3.2: a superscription/, fn ->
        Net.book_rows(@psalms, [%{"chapter" => "3", "verse" => "2", "text" => superscription}])
      end

      assert_raise ArgumentError, ~r/Hab.3.1: a superscription/, fn ->
        Net.book_rows({"Hab", "Habakkuk", 3}, [
          %{"chapter" => "3", "verse" => "1", "text" => superscription}
        ])
      end

      assert_raise ArgumentError, ~r/outside the book/, fn ->
        Net.book_rows({"Rut", "Ruth", 4}, [%{"chapter" => "5", "verse" => "1", "text" => "x"}])
      end
    end

    test "refuses a verse given twice" do
      item = %{"chapter" => "1", "verse" => "1", "text" => "x"}

      assert_raise ArgumentError, ~r/repeated/, fn ->
        Net.book_rows({"Rut", "Ruth", 4}, [item, item])
      end
    end
  end

  test "the NET row carries the publisher's acknowledgement exactly" do
    assert Net.translation().copyright ==
             "Scripture quoted by permission. Quotations designated (NET) are from the NET Bible® " <>
               "copyright ©1996, 2019 by Biblical Studies Press, L.L.C. http://netbible.com " <>
               "All rights reserved."

    assert %{key: "net", abbreviation: "NET", url: "http://netbible.org"} = Net.translation()
  end

  test "the digest depends on every book's checksum, in order" do
    a = Net.digest([{"Gen", "aa"}, {"Exo", "bb"}])
    assert a == Net.sha256("Gen\taa\nExo\tbb\n")
    refute a == Net.digest([{"Exo", "bb"}, {"Gen", "aa"}])
  end
end
