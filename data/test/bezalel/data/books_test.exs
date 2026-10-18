defmodule Bezalel.Data.BooksTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.Books
  alias Bezalel.Study.Reference

  doctest Books

  test "the 66 books with the Protestant canon's 1,189 chapters" do
    assert Enum.count(Books.all()) == 66
    assert Enum.sum_by(Books.all(), &elem(&1, 2)) == 1189
    assert Books.all() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 66
  end

  test "every code is a book code of the study packs" do
    for {code, name, _chapters} <- Books.all() do
      assert Reference.book_code(code) == code
      assert Reference.book_code(name) == code
    end
  end

  test "codes the packs spell unusually" do
    codes = Map.new(Books.all(), fn {code, name, _chapters} -> {name, code} end)

    assert %{
             "Song of Songs" => "Sng",
             "Ezekiel" => "Ezk",
             "Joel" => "Jol",
             "Nahum" => "Nam",
             "Mark" => "Mrk",
             "John" => "Jhn",
             "Jude" => "Jud",
             "Psalms" => "Psa"
           } = codes
  end
end
