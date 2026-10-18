defmodule Bezalel.Study.Tools.GetCrossReferencesTest do
  # Ported from studybible-mcp's tests/test_tool_handlers.py
  # (get_cross_references), against the fixture packs, which hold every
  # TSK cross reference from their chapters.
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Citation, Preferences}
  alias Bezalel.Study.Tools.GetCrossReferences

  # studybible-mcp's default was four; the ported cases keep it as the
  # user's setting.
  @four Preferences.new(limit: 4)

  defp ok(args, prefs \\ @four) do
    assert {:ok, result} = GetCrossReferences.result(args, prefs)
    GetCrossReferences.render(result)
  end

  # Targets in printed order, back in 'Rom.5.8' form, with their votes.
  defp targets(text) do
    for [_, book, chapter, verse, votes] <-
          Regex.scan(~r/^- (\S+) (\d+):(\d+)  \*\(votes: (\d+)\)\*$/m, text),
        do: {"#{book}.#{chapter}.#{verse}", String.to_integer(votes)}
  end

  test "the user's default cap (four here) keeps the four strongest, by votes" do
    text = ok(%{"reference" => "John 3:16"})

    assert text =~
             ~r/\A## Cross-References for John 3:16\n\n_4 reference\(s\) returned \(cap limit=4;/

    assert text =~
             "TSK = Treasury of Scripture Knowledge._\n" <>
               "Source: [John 3:16 cross references](https://www.openbible.info/labs/cross-references/search?q=John+3%3A16)\n\n"

    refute text =~ "Source: TSK"

    assert text =~
             "### TSK — 4\n- Rom 5:8  *(votes: 986)*\n" <>
               "  Source: [Romans 5:8](https://netbible.org/bible/Romans+5:8)\n"

    assert targets(text) == [
             {"Rom.5.8", 986},
             {"1Jn.4.9", 700},
             {"Rom.8.32", 511},
             {"Jhn.3.15", 503}
           ]
  end

  test "the queried verse's TSK page and each target verse in the user's translation are the citations" do
    assert {:ok, result} = GetCrossReferences.result(%{"reference" => "John 3:16"}, @four)

    assert [
             %Citation{
               work: "tsk",
               url: "https://www.openbible.info/labs/cross-references/search?q=John+3%3A16"
             },
             %Citation{work: "net", url: "https://netbible.org/bible/Romans+5:8"},
             %Citation{work: "net", url: "https://netbible.org/bible/1+John+4:9"},
             %Citation{work: "net"},
             %Citation{work: "net", url: "https://netbible.org/bible/John+3:15"}
           ] = GetCrossReferences.citations(result)

    assert {:ok, bsb} =
             GetCrossReferences.result(
               %{"reference" => "John 3:16"},
               Preferences.new(limit: 1, translation: "bsb")
             )

    assert [%Citation{work: "tsk"}, %Citation{url: "https://biblehub.com/romans/5-8.htm"}] =
             GetCrossReferences.citations(bsb)

    assert {:ok, {:details, _text, %{citations: [%Citation{work: "tsk"} | _]}}} =
             GetCrossReferences.run(%{"reference" => "John 3:16"}, %{})

    assert GetCrossReferences.citations(%{rows: []}) == []
  end

  test "the default cap is the user's limit: 8 by default, capped only by the rows there are" do
    assert Enum.count(targets(ok(%{"reference" => "John 3:16"}, %Preferences{}))) == 8
    assert Enum.count(targets(ok(%{"reference" => "John 3:16"}, Preferences.new(limit: 2)))) == 2
    # An explicit limit still wins.
    assert Enum.count(targets(ok(%{"reference" => "John 3:16", "limit" => 3}))) == 3
  end

  test "with the theme chains switched off a theme is an error; verse cross references stay" do
    prefs = Preferences.new(excluded_sources: ["crossrefs:themes"])

    assert {:error, "The user has switched off Thematic cross-reference chains" <> _} =
             GetCrossReferences.result(%{"theme" => "atonement"}, prefs)

    assert {:ok, %{rows: [_ | _]}} =
             GetCrossReferences.result(%{"reference" => "John 3:16"}, prefs)
  end

  test "Exodus 31:3, signal-poor, keeps its weaker links rather than returning one" do
    assert targets(ok(%{"reference" => "Exodus 31:3"})) == [
             {"Exo.35.31", 26},
             {"1Ki.7.14", 17},
             {"Isa.28.26", 17},
             {"1Co.12.4", 16}
           ]
  end

  test "a signal-rich verse drops its tier-1 (under 20 votes) rows" do
    # John 3:14 has three links of 20+ votes; the fourth strongest has 16.
    assert targets(ok(%{"reference" => "John 3:14"})) ==
             [{"Num.21.7", 81}, {"Jhn.8.28", 38}, {"Jhn.12.32", 25}]
  end

  test "source 'tsk' and min_strength turn the suppression off; min_strength floors votes" do
    long_tail = targets(ok(%{"reference" => "John 3:14", "source" => "tsk", "limit" => 20}))
    assert Enum.count(long_tail) == 12
    assert List.last(long_tail) == {"Luk.24.20", 6}

    assert Enum.count(targets(ok(%{"reference" => "John 3:14", "min_strength" => 0}))) == 4

    floored = targets(ok(%{"reference" => "John 3:14", "min_strength" => 12, "limit" => 20}))
    assert Enum.all?(floored, fn {_, votes} -> votes >= 12 end)
    assert {"Mat.26.54", 12} in floored
    refute {"Luk.18.31", 11} in floored
  end

  test "a theme returns its curated chain" do
    text = ok(%{"theme" => "atonement"})

    assert text =~
             ~r/\A## Cross-References: atonement\nSource: \[Thematic chains\]\(https:\/\/github\.com\/djayatillake\/studybible-mcp\)\n\n/

    assert text =~
             "- **Romans 3:25**: Propitiation by His blood\n" <>
               "  Source: [Romans 3:25](https://netbible.org/bible/Romans+3:25)\n"

    assert text =~ "- **1 Peter 2:24**: Bore our sins in His body\n"
    assert ok(%{"theme" => "holy spirit"}) =~ "## Cross-References: holy spirit"

    # A range is linked at its first verse, labelled as the chain gives it.
    assert {:ok, result} = GetCrossReferences.result(%{"theme" => "salvation_by_grace"}, @four)

    assert [
             %Citation{work: "studybible"},
             %Citation{work: "net", url: "https://netbible.org/bible/Genesis+15:6"},
             %Citation{
               work: "net",
               label: "Romans 3:21-26",
               url: "https://netbible.org/bible/Romans+3:21"
             }
             | _
           ] = GetCrossReferences.citations(result)
  end

  test "no match, a bad source and no arguments" do
    assert ok(%{"reference" => "not a verse"}) == "No cross-references found for not a verse."

    assert ok(%{"reference" => "not a verse", "source" => "tsk"}) ==
             "No cross-references found for not a verse. (source filter: tsk)"

    assert ok(%{"theme" => "eschatology"}) ==
             "No cross-references found for theme 'eschatology'."

    assert {:error, "source must be 'tsk'" <> _} =
             GetCrossReferences.run(%{"reference" => "John 3:16", "source" => "ch"}, %{})

    assert GetCrossReferences.run(%{}, %{}) ==
             {:error, "Please provide either 'reference' or 'theme'."}
  end

  test "a single-chapter citation is expanded" do
    assert ok(%{"reference" => "Jude 3"}) =~ "## Cross-References for Jude 1:3"
  end
end
