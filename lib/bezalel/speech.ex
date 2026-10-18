defmodule Bezalel.Speech do
  @moduledoc """
  A reply as words to read aloud: what every app hands its text-to-speech
  (the phone's `Mob.Speech`, the browser's `speechSynthesis`), so a reply
  sounds the same everywhere.

  The caller passes the reply's SUMMARY (its answer), not its thinking or
  tool calls. `speakable/1` reads the Markdown as a listener would hear it:

    * headings, list items and table rows become sentences of their own; a
      table row reads its column names with its cells ("Word: ruach,
      Meaning: spirit."); code blocks and thematic breaks are dropped,
      inline code keeps its text;
    * emphasis and quote marks go; a link reads as its text; images,
      footnote marks, HTML tags and URLs are dropped;
    * Hebrew and Greek (which a voice for English can't read) are replaced
      by the transliteration the model gave in parentheses right after
      them ("רוּחַ (ruach)" is "ruach"), else dropped with the parenthesis
      they leave empty; a Strong's number in parentheses is dropped;
    * a verse reference reads as said aloud: "Ex 31:3" is "Exodus 31
      verse 3", "1 Cor 13:4-7" "First Corinthians 13 verses 4 to 7", "Luke
      19:45-20:2" "Luke 19 verse 45 to 20 verse 2"; "v. 3" is "verse 3",
      "vv. 3-5" "verses 3 to 5".
  """

  alias Bezalel.Agent.Patterns
  alias Bezalel.Study.Reference

  @ordinals %{"1" => "First", "2" => "Second", "3" => "Third", "4" => "Fourth"}

  @doc "The reply's `markdown` (its summary) as plain text for text-to-speech."
  @spec speakable(String.t()) :: String.t()
  def speakable(markdown) when is_binary(markdown) do
    markdown
    |> String.replace(["\r\n", "\r"], "\n")
    |> String.split("\n")
    |> blocks()
    |> Enum.flat_map(&speak/1)
    |> Enum.join("\n")
  end

  # ── Blocks ───────────────────────────────────────────────────────────────

  # The lines as blocks: {:line, text} (a heading), {:para, [lines]} (a
  # paragraph, a quote, a list item and its continuation) and
  # {:table, [rows]}. Code blocks and breaks are left out.
  defp blocks(lines) do
    {blocks, open, _fence} = Enum.reduce(lines, {[], nil, false}, &block/2)
    Enum.reverse(close(open, blocks))
  end

  defp block(line, {blocks, open, fence}) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, ["```", "~~~"]) -> {close(open, blocks), nil, not fence}
      fence -> {blocks, nil, fence}
      trimmed == "" -> {close(open, blocks), nil, false}
      String.starts_with?(trimmed, "|") -> table_line(trimmed, blocks, open)
      Regex.match?(Patterns.get(:md_break), line) -> {close(open, blocks), nil, false}
      true -> text_line(line, blocks, open)
    end
  end

  defp table_line(line, blocks, {:table, rows}), do: {blocks, {:table, [line | rows]}, false}
  defp table_line(line, blocks, open), do: {close(open, blocks), {:table, [line]}, false}

  defp text_line(line, blocks, open) do
    stripped = Regex.replace(Patterns.get(:md_block_mark), line, "")

    cond do
      Regex.match?(Patterns.get(:heading), line) ->
        {[{:line, stripped} | close(open, blocks)], nil, false}

      Regex.match?(Patterns.get(:list_item), line) ->
        {close(open, blocks), {:para, [stripped]}, false}

      match?({:para, _}, open) ->
        {:para, lines} = open
        {blocks, {:para, [stripped | lines]}, false}

      true ->
        {close(open, blocks), {:para, [stripped]}, false}
    end
  end

  defp close(nil, blocks), do: blocks
  defp close({kind, lines}, blocks), do: [{kind, Enum.reverse(lines)} | blocks]

  defp speak({:line, text}), do: sentence(text)
  defp speak({:para, lines}), do: lines |> Enum.join(" ") |> sentence()

  defp speak({:table, rows}) do
    rows = Enum.map(rows, &cells/1)

    case rows do
      [header, rule | data] when is_list(rule) ->
        if rule_row?(rule),
          do: Enum.flat_map(data, &row(header, &1)),
          else: Enum.flat_map(rows, &row(nil, &1))

      _ ->
        Enum.flat_map(rows, &row(nil, &1))
    end
  end

  defp cells(line), do: line |> String.trim() |> String.trim("|") |> String.split("|")

  defp rule_row?(cells),
    do: Regex.match?(Patterns.get(:md_table_rule), Enum.join(cells, "|"))

  defp row(header, cells) do
    names = if header, do: Enum.map(header, &inline/1), else: List.duplicate("", length(cells))

    names
    |> Enum.zip(Enum.map(cells, &inline/1))
    |> Enum.reject(fn {_name, cell} -> cell == "" end)
    |> Enum.map_join(", ", fn
      {"", cell} -> cell
      {name, cell} -> "#{name}: #{cell}"
    end)
    |> sentence()
  end

  # One block's text as a sentence: inline Markdown read, ended with a
  # stop so the voice pauses.
  defp sentence(text) do
    case inline(text) do
      "" -> []
      text -> [if(Regex.match?(Patterns.get(:speech_ending), text), do: text, else: text <> ".")]
    end
  end

  # ── Inline ───────────────────────────────────────────────────────────────

  # Whitespace is collapsed first: no pattern below meets a long run of it.
  defp inline(text) do
    text
    |> String.split()
    |> Enum.join(" ")
    |> replace(:md_image, "")
    |> replace(:md_link, "\\1")
    |> replace(:md_autolink, "")
    |> replace(:url, "")
    |> replace(:md_footnote, "")
    |> replace(:html_tag, " ")
    |> replace(:strongs_paren, "")
    |> original()
    |> references()
    |> String.replace(["**", "__", "~~", "`", "*"], "")
    |> replace(:md_underscore, "")
    |> String.replace(["→", "->", "⇒"], " to ")
    |> String.replace("&", " and ")
    |> String.replace(["·", "•", "|"], ", ")
    |> replace(:paren_open_punct, "(")
    |> replace(:paren_close_punct, ")")
    |> replace(:empty_paren, "")
    |> String.split()
    |> Enum.join(" ")
    |> replace(:space_before_punct, "\\1")
    |> replace(:punct_run, "\\1")
    |> replace(:pause_run, "\\1")
    |> String.trim_leading(", ")
  end

  defp replace(text, pattern, with), do: Regex.replace(Patterns.get(pattern), text, with)

  # Hebrew and Greek: the transliteration in the parenthesis after a run,
  # when it has one (and is in Latin letters), else nothing.
  defp original(text) do
    Regex.replace(Patterns.get(:original_run), text, fn whole, tr ->
      cond do
        tr == "" -> drop_script(whole)
        Regex.match?(Patterns.get(:original_char), tr) -> "(#{drop_script(tr)})"
        true -> tr
      end
    end)
  end

  # Hebrew or Greek with no transliteration: gone, with its marks and the
  # emphasis around it.
  defp drop_script(text) do
    text
    |> replace(:original_char, "")
    |> replace(:marks, "")
    |> String.replace(~w(* _), "")
  end

  # "Ex 31:3" as "Exodus 31 verse 3"; text before the book's name that the
  # pattern took with it ("In Genesis 1:1") stays as it was.
  defp references(text) do
    Patterns.get(:speech_reference)
    |> Regex.replace(text, fn whole, book, c1, v1, c2, v2 ->
      case book_in(book) do
        {before, name} -> before <> spoken(name, c1, v1, c2, v2)
        nil -> whole
      end
    end)
    |> then(
      &Regex.replace(Patterns.get(:verse_abbreviation), &1, fn _, v ->
        if v == "vv", do: "verses ", else: "verse "
      end)
    )
    |> replace(:verse_range, "\\1 to \\2")
  end

  # The longest run of words at the end of `book` that names a book: the
  # words before it, and the book's name to say.
  defp book_in(book) do
    words = String.split(book, " ", trim: true)

    Enum.find_value(0..(length(words) - 1)//1, fn drop ->
      {before, rest} = Enum.split(words, drop)
      candidate = rest |> Enum.join(" ") |> String.trim_trailing(".")

      with code when is_binary(code) <- Reference.book_code(candidate),
           name when is_binary(name) <- Reference.book_name(code) do
        {Enum.map_join(before, &(&1 <> " ")), say_name(name)}
      else
        _ -> nil
      end
    end)
  end

  defp say_name(name) do
    case String.split(name, " ", parts: 2) do
      [digit, rest] when is_map_key(@ordinals, digit) -> "#{@ordinals[digit]} #{rest}"
      _ -> name
    end
  end

  defp spoken(name, c1, v1, "", ""), do: "#{name} #{c1} verse #{v1}"
  defp spoken(name, c1, v1, "", v2), do: "#{name} #{c1} verses #{v1} to #{v2}"
  defp spoken(name, c1, v1, c1, v2), do: "#{name} #{c1} verses #{v1} to #{v2}"
  defp spoken(name, c1, v1, c2, v2), do: "#{name} #{c1} verse #{v1} to #{c2} verse #{v2}"
end
