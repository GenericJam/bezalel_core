defmodule Bezalel.Study.Tools.FindSimilarPassagesTest do
  # Ported from studybible-mcp's tests/test_tool_handlers.py
  # (find_similar_passages), against the fixture packs: the five nearest
  # passages of Exodus 31:3, Psalm 22:18 and John 3:16 as the pack build
  # computed them.
  use ExUnit.Case, async: true

  alias Bezalel.Study.Tools.FindSimilarPassages

  defp ok(args) do
    assert {:ok, text} = FindSimilarPassages.run(args, %{})
    text
  end

  defp ranked(text) do
    for [_, rank, ref, percent] <- Regex.scan(~r/^### (\d+)\. (.+) \(([\d.]+)% similar\)$/m, text),
        do: {String.to_integer(rank), ref, percent}
  end

  test "ranked by similarity, default four, with the caution and the source verse" do
    text = ok(%{"reference" => "Psalm 22:18"})

    assert text =~
             ~r/\A## Passages Similar to Psalm 22:18 \(BSB\)\n\n\*\*Source\*\*: They divide my garments among them and cast lots for my clothing\.\n/

    assert text =~ "Hermeneutical Caution"

    assert ranked(text) == [
             {1, "Isa.3.18 - Isa.4.1", "75.0"},
             {2, "Jhn.19.23 - Jhn.19.25", "73.0"},
             {3, "Ezk.27.1 - Ezk.27.36", "72.6"},
             {4, "Jol.2.28(3.1) - Jol.3.8(4.8)", "72.6"}
           ]

    # The quotation's passage, in the BSB, with its genre against the psalm's.
    assert text =~ "⚡ **Genre**: gospel (source is psalm)"
    assert text =~ "They divided My garments among them, and cast lots for My clothing."
    assert text =~ "*(3 verses in this passage)*"
  end

  test "the limit argument" do
    assert Enum.count(ranked(ok(%{"reference" => "Psalm 22:18", "limit" => 3}))) == 3
    assert Enum.count(ranked(ok(%{"reference" => "Exodus 31:3", "limit" => 5}))) == 5
  end

  test "a passage of the same genre gets no genre line; a long one is cut at 500 characters" do
    text = ok(%{"reference" => "Exodus 31:3"})
    [first | _] = String.split(text, "### 2.")
    assert first =~ "### 1. Exo.35.30 - Exo.36.7 (79.1% similar)"
    refute first =~ "⚡ **Genre**"

    [_, ezekiel] = String.split(ok(%{"reference" => "Psalm 22:18"}), "### 3. ")
    preview = ezekiel |> String.split("\n\n") |> Enum.at(2)
    assert String.ends_with?(preview, "...")
    assert String.length(preview) == 503
  end

  test "a verse not in the pack is not replaced by a neighbour" do
    assert ok(%{"reference" => "Genesis 50:1"}) ==
             "No similar passages found for Genesis 50:1. The verse may not be in the database."
  end

  test "a reference is required" do
    assert FindSimilarPassages.run(%{"reference" => ""}, %{}) ==
             {:error, "Please provide a verse reference (e.g., 'John 3:16')."}
  end

  test "result/1 gives the similarities and previews as data" do
    {:ok, result} = FindSimilarPassages.result(%{"reference" => "John 3:16", "limit" => 1})
    assert result.source.reference == "Jhn.3.16"

    assert [
             %{
               reference: "Act.17.22 - Act.17.31",
               similarity: 0.783,
               verse_count: 10,
               preview: preview
             }
           ] =
             result.passages

    assert Enum.count(preview) == 10
  end
end
