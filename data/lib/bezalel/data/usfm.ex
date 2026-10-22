defmodule Bezalel.Data.Usfm do
  @moduledoc """
  The verse text of one USFM book file, as `translation_verses` rows: the
  JPS 1917 from eBible.org and unfoldingWord's ULT and UST from Door43
  (`Bezalel.Data.Jps`, `Bezalel.Data.Door43`).

  From the markup:

  - the words are kept as given, with the markup removed: a word's
    attributes (`\\w word|x-occurrence="1"\\w*`), the alignment and section
    milestones (`\\zaln-s |…\\*`, `\\zaln-e\\*`, `\\ts\\*`) and Selah's
    character style (`\\qs …\\qs*`, keeping "Selah");
  - a Psalm superscription (`\\d`, before or at the start of verse 1)
    becomes verse 0 of its chapter, the study packs' convention
    (`Psa.3.0`);
  - footnotes (`\\f …\\f*`) are dropped, as the NET import drops its note
    markers, and so are the book's header lines (`\\id`, `\\h`, `\\toc1`…,
    `\\mt1`, `\\cl`) and headings: section headings and their references
    (`\\s1`, `\\sr`, `\\r`), the Psalter's book headings (`\\ms1`), the
    acrostics' Hebrew letters (`\\qa`) and speaker labels (`\\sp`);
  - a paragraph or poetry marker (`\\p`, `\\q1`, `\\b`, …) becomes a space,
    then runs of whitespace collapse to one space;
  - a verse bridge (`\\v 17-18`) is kept whole on its first verse and
    listed in `bridges`.

  Anything else (an unknown marker, text outside a verse, a superscription
  outside a Psalm's first verse, an unclosed word or footnote) raises, so a
  changed source stops the build instead of slipping text in or out.
  """

  @header ~w(id usfm ide h toc1 toc2 toc3 mt1 mt2 cl rem)
  @headings ~w(ms1 s1 s2 sr r sp qa)
  @paragraphs ~w(p m pm pmo pmc pmr pi1 pi2 q1 q2 q3 q4 qm1 qm2 li1 li2 mi nb b)
  @milestones ~w(zaln-s zaln-e ts)
  @footnote ~w(fr fk fq fqa ft fv fq* fqa* fk* fv*)

  @type row :: %{
          reference: String.t(),
          book: String.t(),
          chapter: pos_integer(),
          verse: non_neg_integer(),
          text: String.t()
        }

  @typedoc """
  A book's rows in canonical order; the references the source gives
  without text (`empty`); the headings dropped (`{reference, marker,
  text}`, the reference where the heading stands, or the book code before
  the first chapter); the footnotes dropped (`{reference, text}`); the
  verse bridges kept on their first verse (`{reference, "17-18"}`).
  """
  @type book :: %{
          rows: [row()],
          empty: [String.t()],
          headings: [{String.t(), String.t(), String.t()}],
          footnotes: [{String.t(), String.t()}],
          bridges: [{String.t(), String.t()}]
        }

  @doc """
  The rows of `usfm`, a book file whose `\\id` is `usfm_code`, for the STEP
  book code `book`.
  """
  @spec book(String.t(), String.t(), String.t()) :: book()
  def book(usfm, usfm_code, book) do
    case Regex.run(regex(~S"\A\x{FEFF}?\\id ([A-Z0-9]{3})\b"), usfm) do
      [_, ^usfm_code] -> :ok
      _other -> raise ArgumentError, "#{book}: the file's \\id isn't #{usfm_code}"
    end

    tokens =
      Regex.split(regex(~S"\\(?:\+?[a-z][a-z0-9-]*\*?|\*)"), usfm, include_captures: true)

    state =
      Enum.reduce(tokens, initial(book), fn
        "\\" <> marker, state -> marker(state, marker)
        "", state -> state
        text, state -> text(state, text)
      end)

    if state.skip != nil or state.word != nil do
      raise ArgumentError, "#{where(state)}: unclosed \\#{if state.word, do: "w", else: "f"}"
    end

    state = state |> finish_verse() |> finish_chapter()
    rows = Enum.sort_by(state.rows, &{&1.chapter, &1.verse})
    duplicates = rows |> Enum.frequencies_by(& &1.reference) |> Enum.filter(&(elem(&1, 1) > 1))
    if duplicates != [], do: raise(ArgumentError, "repeated verses #{inspect(duplicates)}")

    %{
      rows: rows,
      empty: Enum.reverse(state.empty),
      headings: Enum.reverse(state.headings),
      footnotes: Enum.reverse(state.footnotes),
      bridges: Enum.reverse(state.bridges)
    }
  end

  defp initial(book) do
    %{
      book: book,
      mode: :header,
      expect: nil,
      skip: nil,
      word: nil,
      chapter: nil,
      verse: nil,
      text: [],
      superscription: [],
      heading: nil,
      footnote: [],
      rows: [],
      empty: [],
      headings: [],
      footnotes: [],
      bridges: []
    }
  end

  # ── Markers ──────────────────────────────────────────────────────────────

  defp marker(%{skip: :milestone} = state, "*"), do: %{state | skip: nil}

  defp marker(%{skip: :footnote} = state, "f*") do
    %{state | skip: nil, footnotes: [{where(state), finish(state.footnote)} | state.footnotes]}
  end

  defp marker(%{skip: :footnote} = state, marker) when marker in @footnote, do: state

  defp marker(%{skip: skip} = state, marker) when skip != nil do
    raise ArgumentError, "#{where(state)}: unexpected \\#{marker} inside a #{skip}"
  end

  defp marker(state, "w"), do: %{state | word: []}

  defp marker(%{word: word} = state, "w*") when word != nil do
    # The space after `\w` delimits the marker; the word follows it.
    word = word |> IO.iodata_to_binary() |> String.split("|", parts: 2) |> hd()
    add(%{state | word: nil}, String.replace_prefix(word, " ", ""))
  end

  defp marker(%{word: word} = state, marker) when word != nil do
    raise ArgumentError, "#{where(state)}: unexpected \\#{marker} inside a word"
  end

  defp marker(state, marker) when marker in @milestones, do: %{state | skip: :milestone}
  defp marker(state, "f"), do: %{state | skip: :footnote, footnote: []}
  defp marker(state, marker) when marker in ["qs", "qs*"], do: add(state, " ")

  defp marker(state, "c"),
    do: %{finish_chapter(finish_verse(end_heading(state))) | expect: :chapter, mode: :none}

  defp marker(state, "v"), do: %{finish_verse(end_heading(state)) | expect: :verse}
  defp marker(state, "d"), do: superscription(end_heading(state))

  defp marker(state, marker) when marker in @paragraphs do
    state = end_heading(state)
    mode = if state.chapter, do: :text, else: :header
    add(%{state | mode: mode}, " ")
  end

  defp marker(state, marker) when marker in @header, do: %{end_heading(state) | mode: :header}

  defp marker(state, marker) when marker in @headings,
    do: %{end_heading(state) | mode: :heading, heading: {marker, []}}

  defp marker(state, marker) do
    raise ArgumentError, "#{where(state)}: unexpected marker \\#{marker}"
  end

  # A superscription: in a Psalm, before verse 1's text.
  defp superscription(%{book: "Psa", verse: nil, chapter: chapter} = state) when chapter != nil,
    do: %{state | mode: :superscription}

  defp superscription(%{book: "Psa", verse: {1, _bridge}} = state) do
    if finish(state.text) == "",
      do: %{state | mode: :superscription},
      else: raise(ArgumentError, "#{where(state)}: a superscription after verse text")
  end

  defp superscription(state) do
    raise ArgumentError, "#{where(state)}: a superscription outside a Psalm's first verse"
  end

  defp end_heading(%{heading: {marker, text}} = state) do
    heading = {where(state), marker, finish(text)}
    %{state | heading: nil, mode: :none, headings: [heading | state.headings]}
  end

  defp end_heading(state), do: state

  # ── Text ─────────────────────────────────────────────────────────────────

  defp text(%{skip: :milestone} = state, _attributes), do: state
  defp text(%{skip: :footnote} = state, text), do: %{state | footnote: [state.footnote | text]}
  defp text(%{word: word} = state, text) when word != nil, do: %{state | word: [word | text]}

  defp text(%{expect: :chapter} = state, text) do
    case Regex.run(regex(~S"\A\s*([0-9]+)\s*\z"), text) do
      [_, chapter] -> %{state | expect: nil, chapter: String.to_integer(chapter)}
      nil -> raise ArgumentError, "#{state.book}: bad chapter number #{inspect(text)}"
    end
  end

  defp text(%{expect: :verse} = state, text) do
    case Regex.run(regex(~S"\A\s*([0-9]+)(?:-([0-9]+))?(?:\s+|\z)"), text) do
      [all | numbers] ->
        state = start_verse(state, numbers)
        add(state, binary_part(text, byte_size(all), byte_size(text) - byte_size(all)))

      nil ->
        raise ArgumentError, "#{where(state)}: bad verse number #{inspect(text)}"
    end
  end

  defp text(state, text), do: add(state, text)

  defp start_verse(%{chapter: nil} = state, _numbers),
    do: raise(ArgumentError, "#{state.book}: a verse before the first chapter")

  defp start_verse(state, [verse]),
    do: %{state | expect: nil, verse: {String.to_integer(verse), nil}, mode: :text, text: []}

  defp start_verse(state, [first, last]) do
    state = start_verse(state, [first])
    bridge = {reference(state.book, state.chapter, String.to_integer(first)), "#{first}-#{last}"}
    %{state | bridges: [bridge | state.bridges]}
  end

  defp add(state, text) do
    case state.mode do
      :text when state.verse != nil -> %{state | text: [state.text | text]}
      :superscription -> %{state | superscription: [state.superscription | text]}
      :heading -> %{state | heading: put_elem(state.heading, 1, [elem(state.heading, 1) | text])}
      :header -> state
      _outside -> blank!(state, text)
    end
  end

  defp blank!(state, text) do
    if String.trim(text) == "",
      do: state,
      else: raise(ArgumentError, "#{where(state)}: text outside a verse #{inspect(text)}")
  end

  # ── Rows ─────────────────────────────────────────────────────────────────

  defp finish_verse(%{verse: nil} = state), do: state

  defp finish_verse(%{verse: {verse, _}} = state) do
    text = finish(state.text)
    state = %{state | verse: nil, text: [], mode: :none}

    if text == "",
      do: %{state | empty: [reference(state.book, state.chapter, verse) | state.empty]},
      else: %{state | rows: [row(state.book, state.chapter, verse, text) | state.rows]}
  end

  defp finish_chapter(%{chapter: nil} = state), do: state

  defp finish_chapter(state) do
    case finish(state.superscription) do
      "" ->
        %{state | superscription: []}

      text ->
        %{
          state
          | superscription: [],
            rows: [row(state.book, state.chapter, 0, text) | state.rows]
        }
    end
  end

  defp where(%{chapter: nil, book: book}), do: book
  defp where(%{verse: nil} = state), do: "#{state.book}.#{state.chapter}"
  defp where(%{verse: {verse, _}} = state), do: reference(state.book, state.chapter, verse)

  @doc "Whitespace collapsed to single spaces, trimmed."
  @spec finish(iodata()) :: String.t()
  def finish(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> then(&Regex.replace(regex("[ \\t\\r\\n]+"), &1, " "))
    |> String.trim()
  end

  defp reference(book, chapter, verse), do: "#{book}.#{chapter}.#{verse}"

  defp row(book, chapter, verse, text) do
    %{
      reference: reference(book, chapter, verse),
      book: book,
      chapter: chapter,
      verse: verse,
      text: text
    }
  end

  defp regex(source) do
    key = {__MODULE__, source}

    case :persistent_term.get(key, nil) do
      nil ->
        regex = Regex.compile!(source, "u")
        :persistent_term.put(key, regex)
        regex

      regex ->
        regex
    end
  end
end
