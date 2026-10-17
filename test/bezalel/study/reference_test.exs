defmodule Bezalel.Study.ReferenceTest do
  # Ported from studybible-mcp's tests/test_lookup_verse.py
  # (test_single_chapter_books_are_cited_by_verse), plus the forms the app
  # sends ("Ex 31:2-3", "Exodus 31", "Jn 3:16").
  use ExUnit.Case, async: true

  alias Bezalel.Study.Reference

  doctest Reference

  for {reference, expected} <- [
        {"Jude 3", "Jude 1:3"},
        {"Jude 1", "Jude 1"},
        {"Obadiah 1", "Obadiah 1"},
        {"Philemon 4–6", "Philemon 1:4-6"},
        {"3 John 4", "3 John 1:4"},
        {"3John 4", "3John 1:4"},
        {"Obadiah 3", "Obadiah 1:3"},
        {"Jude", "Jude 1"},
        {"Jude 1:3", "Jude 1:3"},
        {"John 3", "John 3"},
        {"1 John 3", "1 John 3"},
        {"Psalm 82", "Psalm 82"}
      ] do
    test "single-chapter citation #{inspect(reference)} expands to #{inspect(expected)}" do
      assert Reference.expand_single_chapter(unquote(reference)) == unquote(expected)
    end
  end

  test "verses, ranges and chapters parse in English numbering" do
    assert %{
             book: "Exo",
             book_name: "Ex",
             start_chapter: 31,
             start_verse: 2,
             end_chapter: 31,
             end_verse: 3
           } =
             Reference.parse_passage("Ex 31:2-3")

    assert %{book: "Exo", start_chapter: 31, start_verse: nil, end_chapter: 31, end_verse: nil} =
             Reference.parse_passage("Exodus 31")

    assert %{book: "Jhn", start_chapter: 3, start_verse: 16, end_chapter: 3, end_verse: 16} =
             Reference.parse_passage("Jn 3:16")

    assert %{start_chapter: 19, start_verse: 45, end_chapter: 20, end_verse: 2} =
             Reference.parse_passage("Luke 19:45-20:2")

    # A range of whole chapters, an en dash, the packs' own form.
    assert %{start_chapter: 23, start_verse: nil, end_chapter: 24, end_verse: nil} =
             Reference.parse_passage("Psalm 23-24")

    assert %{start_verse: 1, end_verse: 3} = Reference.parse_passage("Luke 19:1\u20133")
    assert %{book: "Luk", start_chapter: 19, start_verse: 1} = Reference.parse_passage("Luk.19.1")
    assert %{book: "Sng", start_chapter: 2} = Reference.parse_passage("Song of Solomon 2")
    assert %{book: "1Co", start_chapter: 13} = Reference.parse_passage("1 Corinthians 13:4")
    assert Reference.parse_passage("what is love") == nil
  end

  test "an unknown book still parses, to a code with no verses" do
    assert %{book: "Non", book_name: "Nonsense"} = Reference.parse_passage("Nonsense 1:1")
    assert Reference.book_code("Nonsense") == nil
  end

  test "a name missing from the table falls back to its first three letters, title-cased" do
    assert %{book: "2Ch", start_chapter: 7, start_verse: 14} =
             Reference.parse_passage("2 Chron 7:14")

    assert %{book: "1Co"} = Reference.parse_passage("1 Corinth 13:4")
    assert Reference.normalize("1Thes 4:16") == "1Th.4.16"
    assert Reference.normalize("Genes 1:1") == "Gen.1.1"
  end

  test "a verse reference normalizes to the packs' form; anything else is unchanged" do
    assert Reference.normalize("John 3:16") == "Jhn.3.16"
    assert Reference.normalize("Gen. 15:6") == "Gen.15.6"
    assert Reference.normalize("1 Corinthians 13:4-7") == "1Co.13.4"
    assert Reference.normalize("Exodus 31") == "Exodus 31"
  end

  test "a whole chapter is {book, chapter}; verses and chapter ranges are not" do
    assert Reference.single_chapter("Song of Solomon 2") == {"Sng", 2}
    assert Reference.single_chapter("1 John 4") == {"1Jn", 4}
    assert Reference.single_chapter("Romans 8:1") == nil
    assert Reference.single_chapter("Psalm 23-24") == nil
    assert Reference.single_chapter("Genesis") == nil
  end

  test "book codes become Theographic's names in graph references" do
    assert Reference.theographic("Exo.31.2") == "Exod.31.2"
    assert Reference.theographic("Jhn") == "John"
    assert Reference.theographic("Gen.1.1") == "Gen.1.1"
  end
end
