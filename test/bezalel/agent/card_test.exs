defmodule Bezalel.Agent.CardTest do
  # The passage card's translation label and links, from a tool's data.
  use ExUnit.Case, async: true

  alias Bezalel.Agent.Card

  @net %{key: "net", abbreviation: "NET", url: "http://netbible.org"}
  @bsb %{key: "bsb", abbreviation: "BSB", url: "https://bereanbible.com"}

  defp verse(n, translated?) do
    %{
      reference: "Exo.31.#{n}",
      chapter: 31,
      verse: n,
      english: "verse #{n}",
      words: [],
      translated: translated?
    }
  end

  defp lookup(verses, translation) do
    Card.from_tool("lookup_verse", %{
      label: "Exodus 31:2-3",
      reference: "Exo.31.2-3",
      verses: verses,
      translation: translation
    })
  end

  test "the NET label links the first quoted verse's page on netbible.org" do
    card = lookup([verse(2, false), verse(3, true)], @net)
    assert card["version"] == "NET"
    assert card["version_url"] == "https://netbible.org/bible/Exodus+31:3"
  end

  test "each quoted verse has its page in its translation; a gloss-only verse has none" do
    card = lookup([verse(2, false), verse(3, true)], @net)

    assert Enum.map(card["verses"], & &1["url"]) == [
             nil,
             "https://netbible.org/bible/Exodus+31:3"
           ]

    bsb = lookup([verse(2, true)], @bsb)
    assert [%{"url" => "https://biblehub.com/exodus/31-2.htm"}] = bsb["verses"]
  end

  test "the BSB is labelled, with no version link" do
    card = lookup([verse(2, true)], @bsb)
    assert card["version"] == "BSB"
    assert card["version_url"] == nil
    assert Card.text(card) == "2 verse 2 (Exodus 31:2-3, BSB)"
  end

  test "no label when every verse shown is only the gloss" do
    card = lookup([verse(2, false), verse(3, false)], @net)
    assert card["version"] == ""
    assert card["version_url"] == nil
  end

  @ult %{key: "ult", abbreviation: "ULT", url: "https://www.unfoldingword.org/ult"}

  test "a verse the BSB stands in for is labelled BSB on its own row, and in the copied text" do
    card = lookup([verse(2, true), Map.put(verse(3, true), :fallback, true)], @ult)
    assert card["version"] == "ULT"

    assert [%{"url" => "https://preview.door43.org/" <> _} = own, bsb] = card["verses"]
    refute Map.has_key?(own, "version")
    assert %{"version" => "BSB", "url" => "https://biblehub.com/exodus/31-3.htm"} = bsb

    assert Card.text(card) == "2 verse 2 3 verse 3 (BSB) (Exodus 31:2-3, ULT)"
  end

  test "when every quoted verse is the BSB standing in, the card's version is BSB" do
    card = lookup([verse(2, false), Map.put(verse(3, true), :fallback, true)], @ult)
    assert card["version"] == "BSB"
    assert Card.text(card) == "2 verse 2 3 verse 3 (Exodus 31:2-3, BSB)"

    # The NET's link is never a BSB page.
    net = lookup([Map.put(verse(3, true), :fallback, true)], @net)
    assert net["version"] == "BSB"
    assert net["version_url"] == nil
  end
end
