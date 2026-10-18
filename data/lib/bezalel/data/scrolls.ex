defmodule Bezalel.Data.Scrolls do
  @moduledoc """
  ETCBC/dss (Text-Fabric) → the `scrolls` pack's rows.

  **Non-biblical works.** The manuscripts registered in core's
  `Bezalel.Study.Ancient.Scrolls`, one passage per fragment or column label
  (as ETCBC labels them), its lines numbered, as rows of
  `ancient_source_passages` with their search text, exactly as
  studybible-mcp's `corpora/qumran.py` (MIT) made the ancient pack's CD,
  1QS, 1QSa and 1QpHab: `render/2` is its `_render_line`, `index_text/1` and
  `prefix_variants/1` its `ancient_search_index_text` and
  `ancient_search_prefix_variants` with the Qumran removals and gaps (folded
  by core's `Bezalel.Study.Ancient.Passages`, which folds the queries).

  **Biblical scrolls.** Every word ETCBC assigns to a book, chapter and verse
  of the Hebrew Bible, gathered per manuscript and verse with its fragment
  and line labels, rendered the same way, as `dss_biblical_verses` rows.
  ETCBC numbers verses as the Hebrew Bible does; `reference` is the core
  pack's English numbering (its `verses.reference` gives both,
  `Psa.3.0(3.1)`), `source_reference` ETCBC's.

  Rules (the report counts each):

    * the text is ETCBC's signs; nothing is added but the editorial marks of
      `render/2`, and `vacat` for unwritten space;
    * a word whose `book` isn't a book of the Hebrew Bible (ETCBC gives the
      scroll or photograph siglum for unidentified fragments) has no verse
      and isn't imported;
    * a sign belonging to no word has no verse: between two verses, or
      before a line's first verse word or after its last (line ends, empty
      signs), it is left out; inside one verse's words on a line (a `vacat`,
      an unreadable letter) it is kept in that verse's text, where the
      scroll has it;
    * non-biblical scrolls not registered as works (the long tail of small
      fragments) are not imported;
    * an unknown sign type or a non-numeric line label stops the build.
  """

  alias Bezalel.Data.{Books, TextFabric}
  alias Bezalel.Study.Ancient
  alias Bezalel.Study.Ancient.Passages

  @features ~w(otype oslots scroll fragment line biblical type glyph after unc rec rem cor alt vac lang book chapter verse)

  @license "CC BY-NC 4.0"
  @edition "Martin G. Abegg Jr., James E. Bowley and Edward M. Cook, Dead Sea Scrolls " <>
             "transcription, ETCBC/dss Text-Fabric release 2.0.1"

  # Text-critical brackets, by sign feature and value, in opening order
  # (qumran.py's _BRACKETS): modern reconstruction, removal by a modern
  # editor or by the scribe, correction by a modern editor, by the scribe
  # or supralinear, alternative reading, and unwritten space.
  @brackets [
    {"rec", "1", "[", "]"},
    {"rem", "1", "{", "}"},
    {"rem", "2", "{{", "}}"},
    {"cor", "1", "<", ">"},
    {"cor", "2", "<<", ">>"},
    {"cor", "3", "^", "^"},
    {"alt", "1", "(", ")"},
    {"vac", "1", " vacat ", " "}
  ]
  @uncertain "\u05AF"
  @morpheme_break "׳"
  @letters ~w(cons vwl numr)

  # ETCBC book acronyms → STEP codes (the packs' references).
  @books %{
    "Gen" => "Gen",
    "Ex" => "Exo",
    "Lev" => "Lev",
    "Num" => "Num",
    "Deut" => "Deu",
    "Josh" => "Jos",
    "Judg" => "Jdg",
    "Ruth" => "Rut",
    "1Sam" => "1Sa",
    "2Sam" => "2Sa",
    "1Kgs" => "1Ki",
    "2Kgs" => "2Ki",
    "1Chr" => "1Ch",
    "2Chr" => "2Ch",
    "Ezra" => "Ezr",
    "Neh" => "Neh",
    "Esth" => "Est",
    "Job" => "Job",
    "Ps" => "Psa",
    "Prov" => "Pro",
    "Eccl" => "Ecc",
    "Song" => "Sng",
    "Is" => "Isa",
    "Jer" => "Jer",
    "Lam" => "Lam",
    "Ezek" => "Ezk",
    "Dan" => "Dan",
    "Hos" => "Hos",
    "Joel" => "Jol",
    "Amos" => "Amo",
    "Obad" => "Oba",
    "Jonah" => "Jon",
    "Mic" => "Mic",
    "Nah" => "Nam",
    "Hab" => "Hab",
    "Zeph" => "Zep",
    "Hag" => "Hag",
    "Zech" => "Zec",
    "Mal" => "Mal"
  }

  # Sites of the sigla that aren't Qumran caves, by prefix, first match wins.
  @sites [
    {"Mas", "Masada"},
    {"Mur", "Wadi Murabba'at"},
    {"5/6hev", "Nahal Hever (Cave 5/6)"},
    {"Xhev/se", "Nahal Hever or Nahal Se'elim (uncertain)"},
    {"34Se", "Nahal Se'elim (Cave 34)"},
    {"Sdeir", "Wadi Sdeir"},
    {"Arug", "Nahal Arugot"},
    {"Xq", "Qumran (cave unknown)"},
    {"Pam", "unknown (identified on a PAM photograph)"},
    {"X", "unknown provenance"}
  ]

  # The code and data that decide the pack's rows, relative to data/: the
  # importer, core's registry, folding and locator keys, the names.
  @build_inputs ~w(
    lib/bezalel/data/scrolls.ex lib/bezalel/data/scrolls_pack.ex
    lib/bezalel/data/text_fabric.ex lib/bezalel/data/pack.ex
    lib/bezalel/data/books.ex lib/mix/tasks/bezalel.data.scrolls.ex dss_names.json
    ../lib/bezalel/study/ancient.ex ../lib/bezalel/study/ancient/registry.ex
    ../lib/bezalel/study/ancient/scrolls.ex
    ../lib/bezalel/study/ancient/passages.ex ../lib/bezalel/study/patterns.ex
  )

  @doc """
  One checksum of the files that decide the pack's rows (`@build_inputs`,
  relative to `data/`), recorded in `pack_meta.build_sha256` so a publish
  can tell a pack built by other code.
  """
  @spec build_digest() :: String.t()
  def build_digest do
    root = Path.expand("../../..", __DIR__)

    @build_inputs
    |> Enum.map(
      &{&1, :crypto.hash(:sha256, File.read!(Path.join(root, &1))) |> Base.encode16(case: :lower)}
    )
    |> Enum.map(fn {path, sha256} -> [path, ?\t, sha256, ?\n] end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "The Text-Fabric features read, as file names."
  @spec files() :: [String.t()]
  def files, do: Enum.map(@features, &"#{&1}.tf")

  @doc "The passages' edition, licence and source URL for the pinned release."
  @spec provenance(map()) :: %{edition: String.t(), license: String.t(), source_url: String.t()}
  def provenance(pin) do
    %{
      edition: @edition,
      license: @license,
      source_url: "#{pin["repo"]}/tree/#{pin["commit"]}/#{pin["path"]}"
    }
  end

  @doc "The STEP code of an ETCBC book acronym, or nil if it isn't a book of the Hebrew Bible."
  @spec book(String.t() | nil) :: String.t() | nil
  def book(acronym), do: Map.get(@books, acronym)

  # --- Loading ----------------------------------------------------------------

  @doc """
  The parts of ETCBC/dss the pack needs, from `read` (file name → bytes):
  scroll nodes, line nodes (scroll, label, line number, slots), the words
  with a book (book, chapter, verse, slots) and the sign features.
  """
  @spec load((String.t() -> binary())) :: map()
  def load(read) do
    types = TextFabric.types(read.("otype.tf"))
    {_, max_slot} = types["sign"]
    {line_first, line_last} = types["line"]
    {scroll_first, scroll_last} = types["scroll"]
    {word_first, word_last} = types["word"]

    feature = fn name, first, last -> TextFabric.feature(name, read.(name), first, last) end
    slots = TextFabric.slots(read.("oslots.tf"), line_first, word_last)

    scroll_names = feature.("scroll.tf", line_first, scroll_last)
    biblical = feature.("biblical.tf", line_first, scroll_last)
    fragments = feature.("fragment.tf", line_first, line_last)
    numbers = feature.("line.tf", line_first, line_last)

    scrolls =
      for node <- scroll_first..scroll_last//1 do
        %{
          node: node,
          siglum: Map.fetch!(scroll_names, node),
          biblical: Map.has_key?(biblical, node),
          slots: Map.fetch!(slots, node)
        }
      end

    lines =
      for node <- line_first..line_last//1 do
        %{
          node: node,
          siglum: Map.fetch!(scroll_names, node),
          fragment: Map.fetch!(fragments, node),
          line: Map.fetch!(numbers, node),
          slots: Map.fetch!(slots, node)
        }
      end

    books = feature.("book.tf", word_first, word_last)
    chapters = feature.("chapter.tf", word_first, word_last)
    verses = feature.("verse.tf", word_first, word_last)

    words =
      for {node, book} <- books do
        %{
          node: node,
          book: book,
          chapter: Map.fetch!(chapters, node),
          verse: Map.fetch!(verses, node),
          slots: Map.fetch!(slots, node)
        }
      end
      |> Enum.sort_by(& &1.slots.first)

    signs =
      Map.new(~w(type glyph after unc rec rem cor alt vac lang), fn name ->
        {name, feature.("#{name}.tf", 1, max_slot)}
      end)

    %{scrolls: assign_scrolls(lines, scrolls), lines: lines, words: words, signs: signs}
  end

  # Each line's scroll node: lines and scrolls both run in slot order.
  defp assign_scrolls(lines, scrolls) do
    {pairs, _} =
      Enum.map_reduce(lines, scrolls, fn line, [scroll | rest] = remaining ->
        cond do
          line.slots.first in scroll.slots -> {{line.node, scroll}, remaining}
          rest != [] -> assign_scroll(line, rest)
          true -> raise ArgumentError, "line #{line.node} is in no scroll"
        end
      end)

    %{lines: Map.new(pairs), nodes: scrolls}
  end

  defp assign_scroll(line, [scroll | rest] = remaining) do
    if line.slots.first in scroll.slots,
      do: {{line.node, scroll}, remaining},
      else: assign_scroll(line, rest)
  end

  # --- Rendering --------------------------------------------------------------

  @doc """
  The text of `slots` (in order) with ETCBC's editorial brackets: `[ ]`
  modern reconstruction, `{ }` and `{{ }}` removal by an editor or the
  scribe, `< >`, `<< >>` and `^ ^` corrections, `( )` an alternative
  reading, `vacat` unwritten space; a circlet (U+05AF) after a damaged or
  uncertain letter, `◦` an unreadable one, `…` a gap. ETCBC's morpheme
  break (׳) is analytical, not written, and dropped. Whitespace is
  collapsed and an empty pair of brackets keeps a space inside.
  """
  @spec render(Enumerable.t(), map()) :: String.t()
  def render(slots, signs) do
    slots = Enum.to_list(slots)

    {parts, _previous} =
      slots
      |> Enum.zip(tl(slots) ++ [nil])
      |> Enum.reduce({[], []}, fn {slot, next}, {parts, previous} ->
        current = marks(slot, signs)
        following = if next, do: marks(next, signs), else: []

        opens = for i <- current, i not in previous, do: bracket(i, :open)
        closes = for i <- Enum.reverse(current), i not in following, do: bracket(i, :close)

        part = [opens, sign(slot, signs), closes, signs["after"][slot] || ""]
        {[part | parts], current}
      end)

    text =
      parts
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> then(&Regex.replace(regex(~S"\s+"), &1, " "))
      |> String.trim()

    Regex.replace(regex(~S"(\[|\{\{|\{|<<|<|\^|\()(\]|\}\}|\}|>>|>|\^|\))"), text, "\\1 \\2")
  end

  defp marks(slot, signs) do
    for {{feature, value, _, _}, index} <- Enum.with_index(@brackets),
        signs[feature][slot] == value,
        do: index
  end

  defp bracket(index, :open), do: elem(Enum.at(@brackets, index), 2)
  defp bracket(index, :close), do: elem(Enum.at(@brackets, index), 3)

  defp sign(slot, signs), do: sign(signs["type"][slot], signs["glyph"][slot] || "", slot, signs)

  defp sign(type, glyph, slot, signs) when type in @letters,
    do: glyph <> if(signs["unc"][slot], do: @uncertain, else: "")

  defp sign("sep", @morpheme_break, _slot, _signs), do: ""
  # Separators and punctuation as written; the Copper Scroll's (3Q15) Greek
  # letters are text too.
  defp sign(type, glyph, _slot, _signs) when type in ["sep", "punct", "add", "foreign"], do: glyph
  defp sign("missing", _glyph, _slot, _signs), do: "…"
  defp sign("unc", _glyph, _slot, _signs), do: "◦"
  defp sign(type, _glyph, _slot, _signs) when type in ["empty", "term"], do: ""

  defp sign(type, _glyph, slot, _signs),
    do: raise(ArgumentError, "unknown ETCBC sign type #{inspect(type)} at slot #{slot}")

  @doc "How many of `slots` are letters, and how many of those are outside reconstruction."
  @spec letters(Enumerable.t(), map()) :: {non_neg_integer(), non_neg_integer()}
  def letters(slots, signs) do
    Enum.reduce(slots, {0, 0}, fn slot, {all, preserved} ->
      if signs["type"][slot] in @letters,
        do: {all + 1, preserved + if(signs["rec"][slot] == "1", do: 0, else: 1)},
        else: {all, preserved}
    end)
  end

  @doc "'Aramaic' if most letters of `slots` are marked Aramaic (ETCBC `lang` a), else 'Hebrew'."
  @spec language(Enumerable.t(), map()) :: String.t()
  def language(slots, signs) do
    {letters, aramaic} =
      Enum.reduce(slots, {0, 0}, fn slot, {letters, aramaic} ->
        if signs["type"][slot] in @letters,
          do: {letters + 1, aramaic + if(signs["lang"][slot] == "a", do: 1, else: 0)},
          else: {letters, aramaic}
      end)

    if aramaic * 2 > letters, do: "Aramaic", else: "Hebrew"
  end

  # --- Search text ------------------------------------------------------------

  @doc """
  The folded text of the exact search column: modern reconstruction (`[…]`)
  becomes a word break (it is not evidence, and letters either side must not
  join), removals (`{…}`, `{{…}}`) and `vacat` are deleted, the remaining
  editorial signs deleted, and marks and case folded as queries are.
  """
  @spec index_text(String.t()) :: String.t()
  def index_text(original) do
    original
    |> then(&Regex.replace(regex(~S"\[[^\[\]]*\]"), &1, " "))
    |> then(&Regex.replace(regex(~S"\{\{[^{}]*\}\}"), &1, ""))
    |> then(&Regex.replace(regex(~S"\{[^{}]*\}"), &1, ""))
    |> then(&Regex.replace(regex(~S"\bvacat\b"), &1, ""))
    |> Passages.strip_editorial_signs()
    |> Passages.fold()
  end

  @doc """
  The prefix-variant search column: each Hebrew-script word of the index
  text without one, then two, leading prefix letters (ו ב ה ל מ כ ש),
  keeping at least three letters, unless the variant is itself a word of
  the passage; sorted, unique, space-separated.
  """
  @spec prefix_variants(String.t()) :: String.t()
  def prefix_variants(original) do
    words = regex(~S"\w+") |> Regex.scan(index_text(original)) |> List.flatten() |> MapSet.new()

    words
    |> Enum.filter(&Passages.hebrew?/1)
    |> Enum.flat_map(&variants/1)
    |> Enum.reject(&MapSet.member?(words, &1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp variants(word) do
    letters = String.codepoints(word)

    for count <- [1, 2],
        length(letters) - count >= 3,
        Enum.all?(Enum.take(letters, count), &String.contains?("ובהלמכש", &1)),
        do: letters |> Enum.drop(count) |> Enum.join()
  end

  # --- Labels -----------------------------------------------------------------

  @doc """
  A fragment or column label as cited: a column number stays ('5'); an
  ETCBC fragment label becomes 'frg.' and the fragment numbers, joined with
  dashes, a final column numeral spaced off: 'f1_2i' → 'frg. 1–2 i',
  'f2ii+4' → 'frg. 2 ii + 4', 'fA1' → 'frg. A1'. Core's
  `Bezalel.Study.Ancient.fragment_key/1` reads the ETCBC label and this one
  as the same key ('f1-2i').
  """
  @spec display_label(String.t()) :: String.t()
  def display_label(label) do
    case label do
      "f" <> rest when rest != "" ->
        "frg. " <>
          (rest
           |> String.split("+")
           |> Enum.map_join(" + ", &column_space(String.replace(&1, "_", "–"))))

      label ->
        label
    end
  end

  # '1–2i' → '1–2 i', '1aii' → '1a ii': a final lower-case Roman column
  # numeral after the last fragment number and an optional fragment letter.
  defp column_space(part) do
    case Regex.run(regex(~S"^(.*[0-9][a-hA-Z]?)(x{0,3}(?:ix|iv|v?i{0,3}))$"), part) do
      [_, head, roman] when roman != "" -> "#{head} #{roman}"
      _ -> part
    end
  end

  @doc "A span of lines in one label: '5:3–9' for a column number, '1–2 i 3–9' for a fragment."
  @spec span(String.t(), String.t(), String.t()) :: String.t()
  def span(label, first, last) do
    lines = if first == last, do: first, else: "#{first}–#{last}"

    if Regex.match?(regex(~S"^[0-9]+$"), label),
      do: "#{label}:#{lines}",
      else: "#{display_label(label)} #{lines}"
  end

  # --- Non-biblical works -----------------------------------------------------

  @doc """
  The `ancient_source_passages` rows of `works` (core's registry works with
  `siglum`), one per fragment or column label, in ETCBC order, plus a list
  of `{siglum, label, problem}` anomalies for the report. `provenance`:
  `provenance/1`.
  """
  @spec passages(map(), [map()], map()) :: {[map()], [tuple()]}
  def passages(data, works, provenance) do
    by_siglum =
      data.lines
      |> Enum.reject(&data.scrolls.lines[&1.node].biblical)
      |> Enum.group_by(& &1.siglum)

    results =
      Enum.map(works, fn work ->
        lines =
          Map.get(by_siglum, work.siglum) || raise "ETCBC has no non-biblical #{work.siglum}"

        check_one_scroll!(data, work.siglum, lines)

        labels = group_labels(lines)
        check_keys!(work.siglum, labels)

        labels
        |> Enum.with_index(1)
        |> Enum.map(fn {{label, lines}, ordinal} ->
          passage(work, label, ordinal, lines, data.signs, provenance)
        end)
      end)

    rows = Enum.flat_map(results, fn passages -> Enum.map(passages, &elem(&1, 0)) end)
    anomalies = Enum.flat_map(results, fn passages -> Enum.flat_map(passages, &elem(&1, 1)) end)
    {rows, anomalies}
  end

  defp check_one_scroll!(data, siglum, lines) do
    case lines |> Enum.map(&data.scrolls.lines[&1.node].node) |> Enum.uniq() do
      [_one] -> :ok
      nodes -> raise "ETCBC has #{length(nodes)} non-biblical scroll nodes for #{siglum}"
    end
  end

  defp check_keys!(siglum, labels) do
    keys = Enum.map(labels, fn {label, _} -> Ancient.fragment_key(label) end)

    if length(Enum.uniq(keys)) != length(keys) do
      raise "#{siglum}: two labels have one lookup key: #{inspect(keys -- Enum.uniq(keys))}"
    end
  end

  # Labels in order of first appearance, each with its lines in order.
  defp group_labels(lines) do
    {order, groups} =
      Enum.reduce(lines, {[], %{}}, fn line, {order, groups} ->
        order = if Map.has_key?(groups, line.fragment), do: order, else: [line.fragment | order]
        {order, Map.update(groups, line.fragment, [line], &[line | &1])}
      end)

    order |> Enum.reverse() |> Enum.map(&{&1, Enum.reverse(groups[&1])})
  end

  defp passage(work, label, ordinal, lines, signs, provenance) do
    numbered =
      Enum.map(lines, fn line ->
        unless Regex.match?(regex(~S"^[0-9]+$"), line.line) and
                 String.to_integer(line.line) < 1000 do
          raise "#{work.siglum} #{label}: line label #{inspect(line.line)} is not a number below 1000"
        end

        {String.to_integer(line.line), line}
      end)

    numbers = Enum.map(numbered, &elem(&1, 0))
    {first, last} = {List.first(numbers), List.last(numbers)}
    span = span(label, Integer.to_string(first), Integer.to_string(last))
    all_slots = Enum.flat_map(lines, &Enum.to_list(&1.slots))

    original =
      Enum.map_join(numbered, "\n", fn {number, line} ->
        String.trim_trailing("#{number} #{render(line.slots, signs)}")
      end)

    anomalies =
      cond do
        numbers != Enum.sort(numbers) ->
          [{work.siglum, label, "lines out of order"}]

        length(Enum.uniq(numbers)) != length(numbers) ->
          [{work.siglum, label, "a line number repeats"}]

        true ->
          []
      end

    row = %{
      corpus: "qumran",
      author: work.composition,
      work_key: work.key,
      work_title: work.title,
      reference: "#{work.reference_title} #{span}",
      alternate_reference:
        if(work.name not in [nil, work.reference_title], do: "#{work.name} #{span}"),
      book_number: ordinal,
      section_number: Ancient.fragment_key(label),
      section_end: 0,
      editorial_heading: nil,
      text: "",
      original_text: original,
      period_tags: work.periods,
      edition: provenance.edition,
      translation: nil,
      license: provenance.license,
      source_url: provenance.source_url,
      collection: nil,
      sort_start: ordinal * 1000 + Enum.min(numbers),
      sort_end: ordinal * 1000 + Enum.max(numbers),
      original_language: language(all_slots, signs),
      original_license: provenance.license,
      translation_license: nil
    }

    {row, anomalies}
  end

  # --- Biblical scrolls -------------------------------------------------------

  @doc """
  The biblical manuscripts' verse readings. `english` maps an ETCBC
  (Hebrew-numbered) `{book, chapter, verse}` to the core pack's English
  `{chapter, verse}`, or nil when the core pack has no such verse.

  Returns `%{verses: rows, manuscripts: rows, dropped: %{...}}`: a verse row
  per manuscript and verse (a verse appearing twice, apart, in one
  manuscript is two rows, `occurrence` 1 and 2), and the counts the report
  lists.
  """
  @spec biblical(map(), (tuple() -> {integer(), integer()} | nil), %{String.t() => String.t()}) ::
          map()
  def biblical(data, english, names) do
    biblical_lines =
      Enum.filter(data.lines, &data.scrolls.lines[&1.node].biblical)

    Enum.each(biblical_lines, &check_line_label!/1)

    {verse_words, unidentified} = Enum.split_with(data.words, &book(&1.book))

    words_by_line = words_by_line(biblical_lines, verse_words)

    runs =
      Enum.flat_map(biblical_lines, fn line ->
        line
        |> then(&Map.get(words_by_line, &1.node, []))
        |> Enum.chunk_by(&{&1.book, &1.chapter, &1.verse})
        |> Enum.map(&run(line, &1, data.signs))
      end)

    rows = verse_rows(runs, english, names, data)
    order = manuscript_order(data)

    %{
      verses:
        Enum.sort_by(
          rows,
          &{&1.book_index, &1.chapter, &1.verse, order[&1.siglum], &1.occurrence}
        ),
      manuscripts: manuscripts(rows, data, names, order),
      unidentified:
        unidentified
        |> Enum.frequencies_by(& &1.book)
        |> Enum.sort(),
      unmapped: rows |> Enum.reject(& &1.mapped) |> Enum.map(& &1.source_reference),
      wordless_signs:
        wordless_signs(biblical_lines, verse_words ++ unidentified, runs, data.signs)
    }
  end

  # The verse words of each biblical line (words and lines both in slot order).
  defp words_by_line(lines, words) do
    {pairs, _rest} =
      Enum.flat_map_reduce(lines, words, fn line, words ->
        {mine, rest} =
          words
          |> Enum.drop_while(&(&1.slots.first < line.slots.first))
          |> Enum.split_while(&(&1.slots.first in line.slots))

        {if(mine == [], do: [], else: [{line.node, mine}]), rest}
      end)

    Map.new(pairs)
  end

  defp check_line_label!(line) do
    unless Regex.match?(regex(~S"^[0-9]+$"), line.line) and String.to_integer(line.line) < 1000 do
      raise "#{line.siglum} #{line.fragment}: line label #{inspect(line.line)} is not a number below 1000"
    end
  end

  defp run(line, words, signs) do
    [first | _] = words

    slots = first.slots.first..List.last(words).slots.last
    {all, preserved} = letters(slots, signs)

    %{
      siglum: line.siglum,
      scroll: line.node,
      book: book(first.book),
      chapter: String.to_integer(first.chapter),
      verse: String.to_integer(first.verse),
      fragment: line.fragment,
      line: line.line,
      text: render(slots, signs),
      letters: all,
      preserved: preserved,
      slots: slots
    }
  end

  # Consecutive runs of one verse in one manuscript make one row; a verse
  # read again later in the manuscript is its next occurrence.
  defp verse_rows(runs, english, names, data) do
    runs
    |> Enum.chunk_by(&{&1.siglum, &1.book, &1.chapter, &1.verse})
    |> Enum.map_reduce(%{}, fn pieces, seen ->
      row = verse_row(pieces, english, names, data)
      key = {row.siglum, row.reference}
      occurrence = Map.get(seen, key, 0) + 1
      {Map.put(row, :occurrence, occurrence), Map.put(seen, key, occurrence)}
    end)
    |> elem(0)
  end

  defp verse_row([first | _] = pieces, english, names, data) do
    {chapter, verse, mapped} =
      case english.({first.book, first.chapter, first.verse}) do
        {chapter, verse} -> {chapter, verse, true}
        nil -> {first.chapter, first.verse, false}
      end

    letters = pieces |> Enum.map(& &1.letters) |> Enum.sum()
    preserved = pieces |> Enum.map(& &1.preserved) |> Enum.sum()

    %{
      reference: "#{first.book}.#{chapter}.#{verse}",
      book: first.book,
      book_index: Books.index(first.book),
      chapter: chapter,
      verse: verse,
      source_reference: "#{first.book}.#{first.chapter}.#{first.verse}",
      mapped: mapped,
      mt_verse: if(mapped, do: 1, else: 0),
      siglum: first.siglum,
      name: names[first.siglum],
      locator: locator(pieces),
      text: Enum.map_join(pieces, " / ", & &1.text),
      letters: letters,
      preserved_letters: preserved,
      language: language(Enum.flat_map(pieces, &Enum.to_list(&1.slots)), data.signs)
    }
  end

  # 'f35 3' + 'f35 4' → '35 3–4'; '12:13' + '12:14' → '12:13–14'; labels
  # joined with '; '.
  defp locator(pieces) do
    pieces
    |> Enum.chunk_by(& &1.fragment)
    |> Enum.map_join("; ", fn [first | _] = same ->
      span(first.fragment, first.line, List.last(same).line)
    end)
  end

  defp manuscript_order(data) do
    data.scrolls.nodes
    |> Enum.filter(& &1.biblical)
    |> Enum.map(& &1.siglum)
    |> Enum.uniq()
    |> Enum.with_index(1)
    |> Map.new()
  end

  defp manuscripts(rows, data, names, order) do
    by_siglum = Enum.group_by(rows, & &1.siglum)

    data.scrolls.nodes
    |> Enum.filter(& &1.biblical)
    |> Enum.uniq_by(& &1.siglum)
    |> Enum.map(fn %{siglum: siglum} ->
      verses = Map.get(by_siglum, siglum, [])

      %{
        siglum: siglum,
        name: names[siglum],
        site: site(siglum),
        books:
          verses
          |> Enum.sort_by(& &1.book_index)
          |> Enum.map(& &1.book)
          |> Enum.uniq()
          |> Enum.join(" "),
        verses: length(verses),
        reconstructed_only: Enum.count(verses, &(&1.preserved_letters == 0)),
        sort_order: order[siglum]
      }
    end)
  end

  # The signs of biblical lines in no word: `dropped` (outside every verse's
  # span on its line) and `kept` (inside one), counted by sign type.
  defp wordless_signs(lines, words, runs, signs) do
    in_words = words |> Enum.flat_map(&Enum.to_list(&1.slots)) |> MapSet.new()
    in_runs = runs |> Enum.flat_map(&Enum.to_list(&1.slots)) |> MapSet.new()

    {kept, dropped} =
      lines
      |> Enum.flat_map(&Enum.to_list(&1.slots))
      |> Enum.reject(&MapSet.member?(in_words, &1))
      |> Enum.split_with(&MapSet.member?(in_runs, &1))

    %{
      kept: Enum.frequencies_by(kept, &signs["type"][&1]),
      dropped: Enum.frequencies_by(dropped, &signs["type"][&1])
    }
  end

  @doc """
  Where a manuscript was found, by its ETCBC siglum: 'Qumran Cave 4' for
  4Q…, Masada, Wadi Murabba'at, Nahal Hever, Nahal Se'elim, Wadi Sdeir,
  Nahal Arugot, or an unknown provenance. Raises on a siglum it doesn't
  know.
  """
  @spec site(String.t()) :: String.t()
  def site(siglum) do
    case Regex.run(regex(~S"^([0-9]+)Q"), siglum) do
      [_, cave] ->
        "Qumran Cave #{cave}"

      nil ->
        case Enum.find(@sites, &String.starts_with?(siglum, elem(&1, 0))) do
          {_prefix, site} -> site
          nil -> raise ArgumentError, "unknown site for siglum #{inspect(siglum)}"
        end
    end
  end

  # --- Versification ----------------------------------------------------------

  @doc """
  The Hebrew → English verse map from a core pack's `verses.reference`
  values: 'Psa.3.0(3.1)' maps Hebrew `{"Psa", 3, 1}` to `{3, 0}`; a
  reference without a second numbering maps to itself. Returns a function
  of `{book, chapter, verse}` (Hebrew), nil for a verse the core pack lacks.
  """
  @spec english_numbering([String.t()]) :: (tuple() -> {integer(), integer()} | nil)
  def english_numbering(references) do
    pattern = regex(~S"^([^.]+)\.([0-9]+)\.([0-9]+)(?:\(([0-9]+)\.([0-9]+)\))?$")

    {split, same} =
      references
      |> Enum.map(&Regex.run(pattern, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.split_with(&match?([_, _, _, _, _, _], &1))

    hebrew =
      Map.new(split, fn [_, book, chapter, verse, hebrew_chapter, hebrew_verse] ->
        {{book, String.to_integer(hebrew_chapter), String.to_integer(hebrew_verse)},
         {String.to_integer(chapter), String.to_integer(verse)}}
      end)

    plain =
      MapSet.new(same, fn [_, book, chapter, verse] ->
        {book, String.to_integer(chapter), String.to_integer(verse)}
      end)

    fn {_book, chapter, verse} = key ->
      cond do
        Map.has_key?(hebrew, key) -> hebrew[key]
        MapSet.member?(plain, key) -> {chapter, verse}
        true -> nil
      end
    end
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
