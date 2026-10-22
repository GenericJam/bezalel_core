defmodule Bezalel.Data.WitnessesTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.{TextFabric, Witnesses}

  @dt "@licence=Creative Commons Attribution-NonCommercial 4.0 International License"

  defp tf(lines, licence \\ @dt),
    do: Enum.join(["@node", licence, "@valueType=str", "" | lines], "\n") <> "\n"

  # Slots are signs; two books' worth of nodes: book 9, chapter 10, verses
  # 11–12, words 13–16 (word 15 has no trailer: a prefix joined to 16).
  defp sp_files do
    %{
      "otype.tf" => tf(["1-8\tsign", "9\tbook", "10\tchapter", "11-12\tverse", "13-16\tword"]),
      "oslots.tf" => tf(["9\t1-8", "1-8", "1-4", "5-8", "1-2", "3-4", "5", "6-8"]),
      "book.tf" => tf(["9\tNumbers"]),
      "chapter.tf" => tf(["10\t25"]),
      "verse.tf" => tf(["11\t18", "19"]),
      "g_cons_utf8.tf" => tf(["13\tכי", "צררים", "ו", "יהי"]),
      "trailer.tf" => tf(["13\t ", " ", "", " "])
    }
  end

  describe "the Samaritan Pentateuch" do
    test "words joined with their trailers, Hebrew numbering mapped, two verses under one English one" do
      english = fn
        {"Num", 25, 18} -> {25, 18}
        {"Num", 25, 19} -> {26, 1}
      end

      %{verses: [first, second], unmapped: []} =
        Witnesses.samaritan(&Map.fetch!(sp_files(), &1), english)

      assert %{
               reference: "Num.25.18",
               source_reference: "Num.25.18",
               text: "כי צררים",
               mt_verse: 1
             } =
               first

      assert %{reference: "Num.26.1", source_reference: "Num.25.19", text: "ויהי", words: 2} =
               second
    end

    test "a verse the core pack lacks keeps the dataset's number" do
      %{verses: verses, unmapped: unmapped} =
        Witnesses.samaritan(&Map.fetch!(sp_files(), &1), fn _ -> nil end)

      assert unmapped == ["Num.25.18", "Num.25.19"]
      assert Enum.all?(verses, &(&1.mt_verse == 0 and &1.reference == &1.source_reference))
    end

    test "the reader takes DT-UCPH's @licence= spelling and a corpus without lines" do
      assert TextFabric.types(tf(["1-3\tsign", "4\tword"]), ~w(sign word)) ==
               %{"sign" => {1, 3}, "word" => {4, 4}}

      assert_raise ArgumentError, ~r/no "line" nodes/, fn ->
        TextFabric.types(tf(["1-3\tsign"]))
      end

      assert_raise ArgumentError, ~r/no CC BY-NC 4.0 declaration/, fn ->
        TextFabric.feature("x.tf", tf(["a"], "@licence=CC BY 4.0"), 1, 1)
      end
    end
  end

  describe "the SBLGNT apparatus" do
    test "lemma and variants with their sigla; ';' after a siglum separates variants" do
      assert {:ok, %{lemma: "χριστοῦ", lemma_sigla: ["WH"], variants: variants, verses: nil}} =
               Witnesses.parse_note(
                 "1 ⸀χριστοῦ WH\u00A0]\u00A0+\u00A0υἱοῦ θεοῦ Treg NA28; υἱοῦ τοῦ θεοῦ RP",
                 1,
                 1
               )
               |> then(fn {:ok, n} -> {:ok, %{n | lemma: String.replace(n.lemma, "⸀", "")}} end)

      assert variants == [
               %{text: "+ υἱοῦ θεοῦ", sigla: ["Treg", "NA28"]},
               %{text: "υἱοῦ τοῦ θεοῦ", sigla: ["RP"]}
             ]
    end

    test "a Greek question mark stays in the reading; spans, bullets and WH's brackets parse" do
      assert {:ok, %{lemma: "βαπτισθῆναι;", lemma_sigla: ["WH", "Treg"]}} =
               Witnesses.parse_note("36 βαπτισθῆναι; WH Treg ] + 37 εἶπε TR", 8, 36)

      assert {:ok, %{verses: "43–44", variants: [%{text: "", sigla: ["⟦WH⟧"]}]}} =
               Witnesses.parse_note("43–44 ὤφθη δὲ … γῆν. Treg NA28 RP ] ⟦WH⟧", 22, 43)

      assert {:ok, %{lemma: "οὐχ εὑρεθήσεται", lemma_sigla: ["em", "NA28"]}} =
               Witnesses.parse_note("• οὐχ εὑρεθήσεται em NA28 ] εὑρεθήσεται WH", 3, 10)
    end

    test "a note outside the grammar is refused, not guessed" do
      assert {:error, "a reading without sigla"} =
               Witnesses.parse_note("• ἐγείρεται WH ] ἐγηγέρται RP; + 7:53 RP: 53 καὶ", 7, 52)

      assert {:error, "starts with another verse number"} =
               Witnesses.parse_note("17 ὅτι WH ] – RP", 3, 16)

      assert {:error, _} = Witnesses.parse_note("16 ὅτι WH – RP", 3, 16)
    end
  end

  describe "HOTTP" do
    @xml """
    <?xml version="1.0"?>
    <HOTTP_Entries>
      <HOTTP_Entry Id="00015">
        <References><Reference>00100400800004</Reference><Reference>01900300800002</Reference></References>
        <Remark>The MT &lt;span class="hebrew"&gt;ויאמר&lt;/span&gt; may be corrupt.</Remark>
        <Remark-FR>Le TM</Remark-FR>
        <Suggestion>See Remark</Suggestion>
        <SuggestionFR>Voir</SuggestionFR>
        <Alternatives>
          <Alternative><Source>ויאמר</Source><Rating>B (Qere)</Rating><Versions /><Factors />
            <Literal>and Cain said</Literal><LiteralFR>et</LiteralFR></Alternative>
          <Alternative><Source>[נלכה \\ השדה]</Source><Rating />
            <Versions><Version><Text>RSV</Text><Content>"Let us go"</Content></Version></Versions>
            <Factors><Factor>4</Factor><Factor>12 (for/pour \\heb אל\\heb*)</Factor></Factors>
            <Literal>let us go</Literal></Alternative>
        </Alternatives>
      </HOTTP_Entry>
    </HOTTP_Entries>
    """

    test "an entry's English fields without markup, its verses mapped, the French dropped" do
      english = fn
        {"Gen", 4, 8} -> {4, 8}
        {"Psa", 3, 8} -> {3, 7}
      end

      %{entries: [entry], alternatives: [rated, other], verses: verses, french: 3} =
        Witnesses.hottp(@xml, english)

      assert entry.remark == "The MT ויאמר may be corrupt."
      assert %{rating: "B (Qere)", grade: "B", hebrew: "ויאמר", factors: []} = rated
      assert %{grade: nil, factors: ["4", "12 (for/pour אל)"], hebrew: "[נלכה \\ השדה]"} = other
      assert other.renderings == [%{version: "RSV", text: "\"Let us go\""}]

      assert [
               %{reference: "Gen.4.8", segments: [4]},
               %{reference: "Psa.3.7", source_reference: "Psa.3.8"}
             ] =
               verses
    end

    test "unknown markup stops the build" do
      nested = String.replace(@xml, "See Remark", "See <b>Remark</b>")
      assert_raise ArgumentError, ~r/markup inside it/, fn -> Witnesses.hottp(nested, & &1) end

      assert_raise ArgumentError, ~r/unknown markup/, fn -> Witnesses.clean!("a <i>b</i>") end
      assert_raise ArgumentError, ~r/unknown marker/, fn -> Witnesses.clean!("a \\it b") end
      assert Witnesses.clean!("go (\\come) here") == "go (\\come) here"
    end

    test "the glossaries: exactly the four ratings and fifteen factors" do
      ratings =
        Enum.map_join(
          ~w(A B C D),
          "\n",
          &~s(<li><p class="c1"><b>#{&1}</b> - grade #{&1}</p></li>)
        )

      assert [%{grade: "A", meaning: "grade A"} | _] = Witnesses.ratings(ratings)
      assert_raise ArgumentError, fn -> Witnesses.ratings("") end

      factors =
        ~s(<h2 class="c1">A. Factors of evaluation</h2>\n) <>
          Enum.map_join(1..15, "\n", fn n ->
            ~s(<h3 class="c1">#{n}. Name #{n} = Factor #{n}.</h3>\n<p class="c1">Why &quot;#{n}&quot;.</p>)
          end)

      assert [
               %{
                 number: 1,
                 kind: "Factors of evaluation",
                 name: "Name 1",
                 explanation: ~s(Why "1".)
               }
               | _
             ] =
               Witnesses.factors(factors)
    end
  end
end
