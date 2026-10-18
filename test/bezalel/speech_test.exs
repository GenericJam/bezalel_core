defmodule Bezalel.SpeechTest do
  use ExUnit.Case, async: true

  import Bezalel.Speech, only: [speakable: 1]

  test "a word study reads without the Hebrew, its transliteration in its place" do
    reply = """
    ## *Ruach* in Exodus 31

    In **Ex 31:3** God fills Bezalel with the Spirit of God, *ruach* (רוּחַ) *elohim*. The word
    רוּחַ (ruach, "spirit, wind, breath") is used about 389 times (H7307); here it comes
    with חָכְמָה (*chokmah*), "skill" — see [the NET note](https://netbible.org/bible/Exodus+31).
    """

    assert speakable(reply) ==
             """
             Ruach in Exodus 31.
             In Exodus 31 verse 3 God fills Bezalel with the Spirit of God, ruach elohim. \
             The word ruach, "spirit, wind, breath" is used about 389 times; here it comes \
             with chokmah, "skill" — see the NET note.\
             """
  end

  test "Greek with no transliteration is dropped, and the empty parenthesis with it" do
    assert speakable("The *logos* (λόγος) of John 1:1 is the Word: ἐν ἀρχῇ ἦν ὁ λόγος.") ==
             "The logos of John 1 verse 1 is the Word."
  end

  test "a Strong's number after the Hebrew isn't taken for its transliteration" do
    assert speakable("The wind, רוּחַ (H7307), and wisdom, חָכְמָה (Strong's H2451) (chokmah).") ==
             "The wind, and wisdom, chokmah."
  end

  test "references read as said aloud" do
    assert speakable("Compare 1 Cor 13:4-7 with Luke 19:45–20:2 and Song of Solomon 2:1.") ==
             "Compare First Corinthians 13 verses 4 to 7 with Luke 19 verse 45 to 20 verse 2 " <>
               "and Song of Solomon 2 verse 1."

    assert speakable("In Genesis 1:1, and see vv. 3-5 and v. 9.") ==
             "In Genesis 1 verse 1, and see verses 3 to 5 and verse 9."

    # Not a book: left as it is.
    assert speakable("The meeting is at Room 10:30.") == "The meeting is at Room 10:30."
  end

  test "lists, quotes and headings are sentences; code and breaks are dropped" do
    reply = """
    ### Three gifts

    1. Wisdom
    2. Understanding, which
       goes on a second line
    - **Knowledge**

    ---

    > In the beginning was the Word,
    > and the Word was with God.

    ```elixir
    IO.puts("never read")
    ```

    Use `lookup_verse` for the text.
    """

    assert speakable(reply) ==
             """
             Three gifts.
             Wisdom.
             Understanding, which goes on a second line.
             Knowledge.
             In the beginning was the Word, and the Word was with God.
             Use lookup_verse for the text.\
             """
  end

  test "a table reads row by row, each cell with its column" do
    reply = """
    | Word | Hebrew | Meaning |
    |:-----|:------:|--------:|
    | ruach | רוּחַ | spirit |
    | chokmah | חָכְמָה (chokmah) | |
    """

    assert speakable(reply) ==
             "Word: ruach, Meaning: spirit.\nWord: chokmah, Hebrew: chokmah."
  end

  test "URLs, images, footnotes and HTML go" do
    reply =
      "Read it at https://www.biblegateway.com/passage/?search=Ex+31 or <https://netbible.org>." <>
        "![a map](map.png) Bezalel[^1] worked<br>bronze."

    assert speakable(reply) == "Read it at or. Bezalel worked bronze."
  end

  test "an empty reply is nothing to say" do
    assert speakable("") == ""
    assert speakable("```\ncode only\n```") == ""
  end

  test "a long run of punctuation or script is read in linear time" do
    # Each pattern meets it once: a quadratic one took seconds on this.
    reply = String.duplicate("א " <> String.duplicate(", ", 2000), 50)
    {micros, _text} = :timer.tc(fn -> speakable(reply) end)
    assert micros < 1_000_000
  end
end
