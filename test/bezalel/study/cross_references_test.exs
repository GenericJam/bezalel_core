defmodule Bezalel.Study.Tools.GetCrossReferencesTest do
  # Ported from studybible-mcp's tests/test_tool_handlers.py
  # (get_cross_references), against the fixture packs, which hold every
  # TSK cross reference from their chapters.
  use ExUnit.Case, async: true

  alias Bezalel.Study.Tools.GetCrossReferences

  defp ok(args) do
    assert {:ok, text} = GetCrossReferences.run(args, %{})
    text
  end

  # Targets in printed order, back in 'Rom.5.8' form, with their votes.
  defp targets(text) do
    for [_, book, chapter, verse, votes] <-
          Regex.scan(~r/^- (\S+) (\d+):(\d+)  \*\(votes: (\d+)\)\*$/m, text),
        do: {"#{book}.#{chapter}.#{verse}", String.to_integer(votes)}
  end

  test "the default cap keeps the four strongest, by votes" do
    text = ok(%{"reference" => "John 3:16"})

    assert text =~
             ~r/\A## Cross-References for John 3:16\n\n_4 reference\(s\) returned \(cap limit=4;/

    assert text =~ "Source: TSK = Treasury of Scripture Knowledge._"
    assert text =~ "### TSK — 4\n- Rom 5:8  *(votes: 986)*\n"

    assert targets(text) == [
             {"Rom.5.8", 986},
             {"1Jn.4.9", 700},
             {"Rom.8.32", 511},
             {"Jhn.3.15", 503}
           ]
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
    assert text =~ ~r/\A## Cross-References: atonement\n\n/
    assert text =~ "- **Romans 3:25**: Propitiation by His blood\n"
    assert text =~ "- **1 Peter 2:24**: Bore our sins in His body\n"
    assert ok(%{"theme" => "holy spirit"}) =~ "## Cross-References: holy spirit"
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
