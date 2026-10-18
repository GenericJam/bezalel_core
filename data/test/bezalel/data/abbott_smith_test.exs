defmodule Bezalel.Data.AbbottSmithTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.AbbottSmith

  @tei """
  <pb n="iii" />
  <pb n="1" />
  <entry n="α|G1"><orth>α</orth></entry>
  <entry n="Ἀβειληνή"><orth>Ἀβειληνή</orth></entry>
  <pb n="2" />
  <entry n="ἄβυσσος|G12">… in LXX <pb n="3" /> often …</entry>
  <entry n="ἀγάπη|G26">…</entry>
  """

  # The scan numbers pages 2 and 3 (leaves 22, 23) but missed page 1.
  @numbers %{
    "pages" => [
      %{"leafNum" => 21, "pageNumber" => ""},
      %{"leafNum" => 22, "pageNumber" => "2"},
      %{"leafNum" => 23, "pageNumber" => "3"}
    ]
  }

  test "an entry is on the page of the last break before it, a break inside it included" do
    {pages, _tokens} = AbbottSmith.pages(@tei, @numbers)
    assert pages == %{"G1" => "1", "AS_Ἀβειληνή" => "1", "G12" => "2", "G26" => "3"}
  end

  test "a page the scan didn't number gets the leaf index the numbered pages imply" do
    assert {_pages, %{"1" => "n20"}} = AbbottSmith.pages(@tei, @numbers)
  end
end
