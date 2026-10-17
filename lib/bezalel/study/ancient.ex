defmodule Bezalel.Study.Ancient do
  @moduledoc """
  The ancient-source corpora behind `search_ancient_sources` and
  `lookup_ancient_source`: the registry (`Bezalel.Study.Ancient.Registry`),
  citation resolution, locator grammars, per-passage tags and the biblical
  ranges of curated links.

  Ported from studybible-mcp's `corpora/{base,citations,locators}.py`,
  `parse_biblical_range`/`format_biblical_range` (`database.py`) and the
  citation helpers of `server.py` (MIT). Locator numbers are ASCII digits
  (Python's `isdigit` also took other scripts' digits).
  """

  alias Bezalel.Study.Ancient.Registry
  alias Bezalel.Study.{Patterns, Reference}

  @type corpus :: map()
  @type work :: map()
  @type locator :: map()
  @type sort_range :: {integer(), integer()}

  @max_top_level 99_999
  @max_chapter 200
  @max_verse 999

  @book_display_names %{
    "Gen" => "Gen",
    "Exo" => "Exod",
    "Lev" => "Lev",
    "Num" => "Num",
    "Deu" => "Deut",
    "Jos" => "Josh",
    "Jdg" => "Judg",
    "Rut" => "Ruth",
    "1Sa" => "1 Sam",
    "2Sa" => "2 Sam",
    "1Ki" => "1 Kgs",
    "2Ki" => "2 Kgs",
    "1Ch" => "1 Chr",
    "2Ch" => "2 Chr",
    "Ezr" => "Ezra",
    "Neh" => "Neh",
    "Est" => "Esth",
    "Job" => "Job",
    "Psa" => "Ps",
    "Pro" => "Prov",
    "Ecc" => "Eccl",
    "Sng" => "Song",
    "Isa" => "Isa",
    "Jer" => "Jer",
    "Lam" => "Lam",
    "Ezk" => "Ezek",
    "Dan" => "Dan",
    "Hos" => "Hos",
    "Jol" => "Joel",
    "Amo" => "Amos",
    "Oba" => "Obad",
    "Jon" => "Jonah",
    "Mic" => "Mic",
    "Nam" => "Nah",
    "Hab" => "Hab",
    "Zep" => "Zeph",
    "Hag" => "Hag",
    "Zec" => "Zech",
    "Mal" => "Mal",
    "Mat" => "Matt",
    "Mrk" => "Mark",
    "Luk" => "Luke",
    "Jhn" => "John",
    "Act" => "Acts",
    "Rom" => "Rom",
    "1Co" => "1 Cor",
    "2Co" => "2 Cor",
    "Gal" => "Gal",
    "Eph" => "Eph",
    "Php" => "Phil",
    "Col" => "Col",
    "1Th" => "1 Thess",
    "2Th" => "2 Thess",
    "1Ti" => "1 Tim",
    "2Ti" => "2 Tim",
    "Tit" => "Titus",
    "Phm" => "Phlm",
    "Heb" => "Heb",
    "Jas" => "Jas",
    "1Pe" => "1 Pet",
    "2Pe" => "2 Pet",
    "1Jn" => "1 John",
    "2Jn" => "2 John",
    "3Jn" => "3 John",
    "Jud" => "Jude",
    "Rev" => "Rev",
    "Tob" => "Tob",
    "Jdt" => "Jdt",
    "Wis" => "Wis",
    "Sir" => "Sir",
    "Bar" => "Bar",
    "1Ma" => "1 Macc",
    "2Ma" => "2 Macc",
    "3Ma" => "3 Macc",
    "4Ma" => "4 Macc",
    "1Es" => "1 Esd",
    "2Es" => "2 Esd",
    "Man" => "Pr Man",
    "Pss" => "Pss Sol",
    "EsG" => "Add Esth",
    "Lje" => "Ep Jer",
    "Sus" => "Sus",
    "Bel" => "Bel",
    "Ode" => "Odes"
  }

  # --- Registry -------------------------------------------------------------

  @doc "Every corpus, in registry order."
  @spec corpora() :: [corpus()]
  def corpora, do: Registry.corpora()

  @doc "The corpus keys, in registry order."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(corpora(), & &1.key)

  @doc "The corpus `key`, or nil."
  @spec corpus(term()) :: corpus() | nil
  def corpus(key), do: Enum.find(corpora(), &(&1.key == key))

  @doc "Every period tag, in registry order without duplicates."
  @spec periods() :: [String.t()]
  def periods, do: corpora() |> Enum.flat_map(& &1.periods) |> Enum.uniq()

  @doc "The date tiers: key to description."
  @spec tiers() :: %{String.t() => String.t()}
  def tiers, do: Registry.tiers()

  @doc "A link relation's label ('Link' for an unknown relation)."
  @spec relation_label(String.t() | nil) :: String.t()
  def relation_label(relation), do: Map.get(Registry.relations(), relation || "", "Link")

  @doc "The work `key` of `corpus`, or nil."
  @spec work(corpus(), String.t() | nil) :: work() | nil
  def work(corpus, key), do: Enum.find(corpus.works, &(&1.key == key))

  @doc "A work's names: reference title, title, aliases."
  @spec names(work()) :: [String.t()]
  def names(work), do: Enum.uniq([work.reference_title, work.title | work.aliases])

  @doc "A work's reference title with its collection ('Mishnah Shekalim')."
  @spec display_title(work()) :: String.t()
  def display_title(%{collection: nil} = work), do: work.reference_title
  def display_title(work), do: "#{work.collection.title} #{work.reference_title}"

  # --- Tags -----------------------------------------------------------------

  @doc """
  The tag line and tiers of a passage (`corpus` and `work_key` of the row,
  or the default corpus): 'Not Scripture · Jewish history (AD 93–94) ·
  tier A · Niese Greek, Whiston English'. An unregistered corpus is just
  'Not Scripture'.
  """
  @spec row_tag(map(), String.t() | nil) :: {String.t(), [String.t()]}
  def row_tag(row, default_corpus) do
    with %{} = corpus <- corpus(row["corpus"] || default_corpus || ""),
         {%{} = tag, section} <- tag_for(corpus, row["work_key"], row["sort_start"]) do
      {tag_line(tag, section), String.split(tier_for(tag, section), "/")}
    else
      _ -> {"Not Scripture", []}
    end
  end

  defp tag_for(corpus, work_key, sort_start) do
    case work(corpus, work_key || "") do
      nil ->
        {corpus.tag, nil}

      work ->
        tag = work.tag || corpus.tag
        {tag, if(tag && is_integer(sort_start), do: section_at(tag, work, sort_start))}
    end
  end

  # The first dated section of `tag` containing `sort_start`, or nil.
  defp section_at(tag, work, sort_start) do
    Enum.find(tag.sections, &in_section?(&1, work, sort_start))
  end

  defp in_section?(section, work, sort_start) do
    case parse_locator(work.locator, section.locator) do
      {low, high} -> low <= sort_start and sort_start <= high
      nil -> false
    end
  end

  defp tier_for(tag, nil), do: tag.tier
  defp tier_for(tag, %{tier: ""}), do: tag.tier
  defp tier_for(_tag, section), do: section.tier

  defp section_date(tag, nil), do: tag.date
  defp section_date(tag, %{date: ""}), do: tag.date
  defp section_date(_tag, %{name: "", date: date}), do: date
  defp section_date(_tag, %{name: name, date: date}), do: "#{name}, #{date}"

  defp manuscript(tag, nil), do: tag.manuscript
  defp manuscript(tag, section), do: section.manuscript || tag.manuscript

  defp tag_line(tag, section) do
    manuscript = manuscript(tag, section)

    [
      tag.status,
      "#{tag.kind} (#{section_date(tag, section)})",
      "tier #{tier_for(tag, section)}",
      tag.edition
    ]
    |> Kernel.++(if manuscript in [nil, ""], do: [], else: [manuscript])
    |> Enum.join(" · ")
  end

  # --- Locators -------------------------------------------------------------

  @doc "The inclusive sort range of locator text, or nil if it isn't the grammar."
  @spec parse_locator(locator(), String.t()) :: sort_range() | nil
  def parse_locator(locator, text) do
    trimmed = Regex.replace(Patterns.get(:locator_trailing), String.trim(text), "")

    case Regex.split(Patterns.get(:locator_dash), trimmed) do
      [first] when first != "" -> locator_bounds(locator, first, [])
      [first, last] when first != "" and last != "" -> locator_bounds(locator, first, [last])
      _ -> nil
    end
  end

  defp locator_bounds(locator, first, rest) do
    with start when start != nil <- numbers(locator, first, true, locator.depth),
         end_ when end_ != nil <- range_end(locator, start, rest) do
      {low, _} = bounds(locator, start)
      {_, high} = bounds(locator, end_)
      if low <= high, do: {low, high}
    end
  end

  defp range_end(_locator, start, []), do: start

  defp range_end(locator, start, [piece]) do
    levels = length(Regex.split(Patterns.get(:locator_separator), piece))

    case numbers(locator, piece, levels == length(start), length(start)) do
      nil -> nil
      tail -> Enum.take(start, length(start) - length(tail)) ++ tail
    end
  end

  defp numbers(locator, text, includes_top, max_levels) do
    tokens = Regex.split(Patterns.get(:locator_separator), text)

    if Enum.count_until(tokens, max_levels + 1) <= max_levels do
      tokens
      |> Enum.with_index()
      |> Enum.reduce_while([], &collect_number(locator, includes_top, &1, &2))
      |> then(&(&1 && Enum.reverse(&1)))
    end
  end

  defp collect_number(locator, includes_top, {token, index}, acc) do
    case number(locator, token, includes_top and index == 0) do
      nil -> {:halt, nil}
      value -> {:cont, [value | acc]}
    end
  end

  defp number(locator, token, top) do
    value =
      cond do
        Regex.match?(Patterns.get(:ascii_digits), token) -> String.to_integer(token)
        locator.roman and top -> roman_to_int(token)
        true -> nil
      end

    if value != nil and value < level_limit(locator, top) and book_ok?(locator, top, value),
      do: value
  end

  defp level_limit(_locator, true), do: @max_top_level + 1
  defp level_limit(locator, false), do: locator.scale

  defp book_ok?(%{books: books}, true, value) when books != nil, do: value in 1..books//1
  defp book_ok?(_locator, _top, _value), do: true

  @roman_values %{"i" => 1, "v" => 5, "x" => 10, "l" => 50, "c" => 100, "d" => 500, "m" => 1000}

  @doc "The value of a Roman numeral ('vi', 'XIV'), or nil."
  @spec roman_to_int(String.t()) :: non_neg_integer() | nil
  def roman_to_int(text) do
    if text != "" and Regex.match?(Patterns.get(:roman), text) do
      values = text |> String.downcase() |> String.graphemes() |> Enum.map(&@roman_values[&1])

      values
      |> Enum.zip(tl(values) ++ [0])
      |> Enum.map(&roman_value/1)
      |> Enum.sum()
    end
  end

  defp roman_value({value, next}) when value < next, do: -value
  defp roman_value({value, _next}), do: value

  defp bounds(locator, parts) do
    missing = locator.depth - length(parts)

    {key(locator, parts ++ List.duplicate(0, missing)),
     key(locator, parts ++ List.duplicate(locator.scale - 1, missing))}
  end

  defp key(locator, parts), do: Enum.reduce(parts, 0, &(&2 * locator.scale + &1))

  defp levels(locator, key) do
    {parts, top} =
      Enum.reduce(1..(locator.depth - 1)//1, {[], key}, fn _, {parts, key} ->
        {[rem(key, locator.scale) | parts], div(key, locator.scale)}
      end)

    [top | parts]
  end

  @doc "A sort range as locator text ('18.116–119', '18' for a whole book)."
  @spec format_range(locator(), integer(), integer()) :: String.t()
  def format_range(locator, start, end_) do
    {first, last} = collapse(levels(locator, start), levels(locator, end_), locator.scale)
    render = &Enum.join(&1, locator.separator)

    if first == last do
      render.(first)
    else
      shared =
        Enum.zip(Enum.drop(first, -1), last)
        |> Enum.take_while(fn {a, b} -> a == b end)
        |> length()

      "#{render.(first)}–#{render.(Enum.drop(last, shared))}"
    end
  end

  defp collapse([_, _ | _] = first, last, scale) do
    if List.last(first) == 0 and List.last(last) == scale - 1,
      do: collapse(Enum.drop(first, -1), Enum.drop(last, -1), scale),
      else: {first, last}
  end

  defp collapse(first, last, _scale), do: {first, last}

  # --- Citations ------------------------------------------------------------

  @typedoc "A work whose name prefixes a citation; `sort_range` nil if the locator didn't parse."
  @type match :: %{
          corpus: corpus(),
          work: work(),
          locator_text: String.t(),
          sort_range: sort_range() | nil,
          name_length: non_neg_integer()
        }

  @doc "The heading of a match: 'Antiquities 18.116'."
  @spec heading(match()) :: String.t()
  def heading(match), do: String.trim("#{display_title(match.work)} #{match.locator_text}")

  @doc """
  Resolves `citation` ('[corpus alias] [collection] work locator') against
  `corpora`: `{:ok, match}`, `{:ambiguous, candidates}`,
  `{:bad_locator, candidates}` or `:unknown_work`. The longest name match
  whose locator parses wins.
  """
  @spec resolve(String.t(), [corpus()]) ::
          {:ok, match()} | {:ambiguous, [match()]} | {:bad_locator, [match()]} | :unknown_work
  def resolve(citation, corpora) do
    text =
      Patterns.get(:apostrophes)
      |> Regex.replace(:unicode.characters_to_nfc_binary(citation), "")
      |> String.trim()

    case Enum.flat_map(corpora, &work_matches(&1, text)) do
      [] -> :unknown_work
      candidates -> pick(candidates, Enum.filter(candidates, & &1.sort_range))
    end
  end

  defp pick(candidates, []), do: {:bad_locator, longest(candidates)}

  defp pick(_candidates, parsed) do
    case longest(parsed) do
      [match] -> {:ok, match}
      best -> {:ambiguous, best}
    end
  end

  defp longest(pool) do
    length = pool |> Enum.map(& &1.name_length) |> Enum.max()
    Enum.filter(pool, &(&1.name_length == length))
  end

  defp work_matches(corpus, text) do
    {order, matches} =
      for start <- prefix_ends(corpus.aliases, text, 0),
          work <- corpus.works,
          position <- prefix_ends(collection_names(work), text, start),
          name <- names(work),
          end_ = name_end(name, text, position),
          end_ != nil,
          reduce: {[], %{}} do
        acc -> keep_longest(acc, corpus, work, text, end_)
      end

    order |> Enum.reverse() |> Enum.map(&matches[&1])
  end

  # Each work's longest name match (the first among equals), in first-match order.
  defp keep_longest({order, matches}, corpus, work, text, end_) do
    case matches[work.key] do
      %{name_length: length} when end_ <= length ->
        {order, matches}

      best ->
        locator_text = text |> binary_part(end_, byte_size(text) - end_) |> strip_locator()

        match = %{
          corpus: corpus,
          work: work,
          locator_text: locator_text,
          sort_range: parse_locator(work.locator, locator_text),
          name_length: end_
        }

        {if(best, do: order, else: [work.key | order]), Map.put(matches, work.key, match)}
    end
  end

  defp collection_names(%{collection: nil}), do: []
  defp collection_names(%{collection: c}), do: [c.title | c.aliases]

  # Python's str.strip(" .,").
  defp strip_locator(text) do
    text
    |> String.replace(Patterns.get(:locator_strip_left), "")
    |> String.replace(Patterns.get(:locator_strip_right), "")
  end

  defp prefix_ends(names, text, position) do
    ends =
      for name <- names, end_ = name_end(name, text, position), end_ != nil, do: skip(text, end_)

    [position | ends]
  end

  # The position after any spaces, dots and commas at `position`.
  defp skip(text, position) do
    [skipped] =
      Regex.run(
        Patterns.get(:citation_skip),
        binary_part(text, position, byte_size(text) - position)
      )

    position + byte_size(skipped)
  end

  # The byte position after `name` (ignoring case, punctuation, dashes and
  # spacing) if it occurs at `position` of `text`.
  defp name_end(name, text, position) do
    rest = binary_part(text, position, byte_size(text) - position)

    case Regex.run(name_regex(name), rest, return: :index) do
      [{0, length}] -> position + length
      _ -> nil
    end
  end

  # Keyed by a hash of the registry, so a hot-loaded registry with changed
  # names compiles afresh instead of reading the old regexes.
  @names_version :erlang.phash2(Registry.corpora())

  defp name_regex(name) do
    key = {__MODULE__, :names, @names_version}

    regexes =
      case :persistent_term.get(key, nil) do
        nil -> compile_names(key)
        all -> all
      end

    Map.get_lazy(regexes, name, fn -> compile_name(name) end)
  end

  defp compile_names(key) do
    all =
      for corpus <- corpora(),
          name <-
            corpus.aliases ++ Enum.flat_map(corpus.works, &(names(&1) ++ collection_names(&1))),
          into: %{},
          do: {name, compile_name(name)}

    :persistent_term.put(key, all)
    all
  end

  defp compile_name(name) do
    tokens = Patterns.get(:name_token) |> Regex.scan(String.downcase(name)) |> List.flatten()

    Regex.compile!(
      "^" <> Enum.map_join(tokens, "[\\s.,\\-‐‑‒–—]*", &Regex.escape/1) <> "(?![^\\W_])",
      "iu"
    )
  end

  @doc "The citable works, short: names for small corpora, a count and example otherwise."
  @spec citable_works() :: String.t()
  def citable_works do
    Enum.map_join(corpora(), "; ", fn corpus ->
      "#{corpus.label} (#{work_names(corpus.works)}; e.g. '#{corpus.example_citation}')"
    end)
  end

  defp work_names([_, _, _, _, _ | _] = works) do
    collections =
      works |> Enum.filter(& &1.collection) |> Enum.map(& &1.collection.title) |> Enum.uniq()

    case collections do
      [collection] -> "#{collection}, #{length(works)} works"
      _ -> "#{length(works)} works"
    end
  end

  defp work_names(works), do: Enum.map_join(works, ", ", &display_title/1)

  @doc "Work names close to an unrecognised citation's name ('Antiquites' -> 'Antiquities')."
  @spec similar_works(String.t()) :: [String.t()]
  def similar_works(citation) do
    name =
      Patterns.get(:trailing_locator)
      |> Regex.replace(citation, "")
      |> String.trim()
      |> String.downcase()

    # Python's dict: first position, last value.
    {keys, titles} =
      for corpus <- corpora(),
          work <- corpus.works,
          title <- names(work) ++ [display_title(work)],
          reduce: {[], %{}} do
        {keys, titles} ->
          key = String.downcase(title)

          {if(Map.has_key?(titles, key), do: keys, else: [key | keys]),
           Map.put(titles, key, display_title(work))}
      end

    keys
    |> Enum.reverse()
    |> close_matches(name, 3, 0.75)
    |> Enum.map(&titles[&1])
    |> Enum.uniq()
  end

  # difflib.get_close_matches: ratio >= cutoff, best n by (score, word) descending.
  defp close_matches(possibilities, word, n, cutoff) do
    b = String.codepoints(word)

    possibilities
    |> Enum.map(&{ratio(String.codepoints(&1), b), &1})
    |> Enum.filter(fn {score, _} -> score >= cutoff end)
    |> Enum.sort(:desc)
    |> Enum.take(n)
    |> Enum.map(&elem(&1, 1))
  end

  defp ratio(a, b) do
    total = length(a) + length(b)
    if total == 0, do: 1.0, else: 2.0 * matched(List.to_tuple(a), List.to_tuple(b)) / total
  end

  # SequenceMatcher's matching characters (no junk: the words are short).
  defp matched(a, b) do
    b2j =
      b |> Tuple.to_list() |> Enum.with_index() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    blocks(a, b2j, 0, tuple_size(a), 0, tuple_size(b))
  end

  defp blocks(a, b2j, alo, ahi, blo, bhi) do
    {i, j, k} = longest_match(a, b2j, alo, ahi, blo, bhi)

    if k == 0 do
      0
    else
      k +
        if(alo < i and blo < j, do: blocks(a, b2j, alo, i, blo, j), else: 0) +
        if(i + k < ahi and j + k < bhi, do: blocks(a, b2j, i + k, ahi, j + k, bhi), else: 0)
    end
  end

  defp longest_match(a, b2j, alo, ahi, blo, bhi) do
    {best, _} =
      Enum.reduce(alo..(ahi - 1)//1, {{alo, blo, 0}, %{}}, fn i, {best, j2len} ->
        b2j
        |> Map.get(elem(a, i), [])
        |> Enum.filter(&(&1 >= blo and &1 < bhi))
        |> Enum.reduce({best, %{}}, &extend(&1, &2, i, j2len))
      end)

    best
  end

  # find_longest_match's step: the match ending at (i, j) is one longer than
  # the one ending at (i - 1, j - 1).
  defp extend(j, {{_, _, size} = best, new}, i, j2len) do
    k = Map.get(j2len, j - 1, 0) + 1
    {if(k > size, do: {i - k + 1, j - k + 1, k}, else: best), Map.put(new, j, k)}
  end

  @doc "A candidate work: 'Antiquities (Josephus, cited by book.section, books 1–20)'."
  @spec candidate(match()) :: String.t()
  def candidate(match) do
    locator = match.work.locator

    grammar =
      if locator.books, do: "#{locator.name}, books 1–#{locator.books}", else: locator.name

    "#{display_title(match.work)} (#{match.corpus.label}, cited by #{grammar})"
  end

  # --- Biblical ranges ------------------------------------------------------

  @doc """
  'Luke 21', 'Luke 21:5', 'Luke 21:5-6' or 'Jude 6' as `{book code, sort
  start, sort end}` (chapter * 1000 + verse), or nil for an unknown book,
  a reversed range or out-of-range numbers.
  """
  @spec biblical_range(String.t()) :: {String.t(), integer(), integer()} | nil
  def biblical_range(reference) do
    case parse_passage_reference(Reference.expand_single_chapter(String.trim(reference))) do
      {_book, code, {chapter, verse, _}, {end_chapter, end_verse, _}} when code != nil ->
        verse = max(verse, 1)
        end_verse = min(end_verse, @max_verse)

        if 1 <= chapter and chapter <= end_chapter and end_chapter <= @max_chapter and
             verse <= @max_verse,
           do: {code, chapter * 1000 + verse, end_chapter * 1000 + end_verse}

      _ ->
        nil
    end
  end

  @doc """
  database.py's `parse_passage_reference`: a verse, range (also across
  chapters) or whole chapter as `{book name, book code or nil, start, end}`
  with `{chapter, verse, suffix}` bounds (a whole chapter runs from verse 0
  to 9999, "~" sorting after every suffix letter); nil when unparseable,
  reversed, or a number is outside SQLite's 64-bit range (it can't be
  bound). No single-chapter expansion.
  """
  @spec parse_passage_reference(String.t()) ::
          {String.t(), String.t() | nil, {integer(), integer(), String.t()},
           {integer(), integer(), String.t()}}
          | nil
  def parse_passage_reference(reference) do
    with %{} = m <- Regex.named_captures(Patterns.get(:biblical_range), String.trim(reference)),
         {start, end_} <- positions(m),
         true <- int64?(start) and int64?(end_),
         true <- end_ >= start do
      book = String.trim(m["book"])
      {book, Reference.book_code(book), start, end_}
    else
      _ -> nil
    end
  end

  @int64_max 0x7FFFFFFFFFFFFFFF

  defp int64?({chapter, verse, _suffix}), do: chapter <= @int64_max and verse <= @int64_max

  # parse_passage_reference's (chapter, verse, suffix) bounds; "~" sorts after
  # every suffix letter.
  defp positions(%{"c1" => c1, "v1" => ""} = m) do
    if m["c2"] != "" or m["s2"] != "" do
      nil
    else
      chapter = String.to_integer(c1)
      end_chapter = if m["v2"] != "", do: String.to_integer(m["v2"]), else: chapter
      {{chapter, 0, ""}, {end_chapter, 9999, "~"}}
    end
  end

  defp positions(m) do
    chapter = String.to_integer(m["c1"])
    start = {chapter, String.to_integer(m["v1"]), String.downcase(m["s1"])}

    if m["v2"] == "" do
      {start, start}
    else
      end_chapter = if m["c2"] != "", do: String.to_integer(m["c2"]), else: chapter
      suffix = if m["s2"] == "", do: "~", else: String.downcase(m["s2"])
      {start, {end_chapter, String.to_integer(m["v2"]), suffix}}
    end
  end

  @doc "A link's range: 'Mark 14:62', 'Gen 6:1–4', 'Heb 9–10', 'Jude 14–15'."
  @spec format_biblical_range(String.t(), integer(), integer(), integer(), integer()) ::
          String.t()
  def format_biblical_range(code, chapter, 1, end_chapter, @max_verse) do
    book = Map.get(@book_display_names, code, code)
    if chapter == end_chapter, do: "#{book} #{chapter}", else: "#{book} #{chapter}–#{end_chapter}"
  end

  def format_biblical_range(code, chapter, verse, chapter, verse) do
    "#{Map.get(@book_display_names, code, code)} #{verse_start(code, chapter, verse, chapter)}"
  end

  def format_biblical_range(code, chapter, verse, end_chapter, end_verse) do
    end_ =
      if chapter == end_chapter, do: "#{end_verse}", else: "#{end_chapter}:#{end_verse}"

    "#{Map.get(@book_display_names, code, code)} " <>
      "#{verse_start(code, chapter, verse, end_chapter)}–#{end_}"
  end

  # A single-chapter book's verses are cited alone: 'Jude 14'.
  defp verse_start(code, 1, verse, 1) do
    if Reference.single_chapter_book?(code), do: "#{verse}", else: "1:#{verse}"
  end

  defp verse_start(_code, chapter, verse, _end_chapter), do: "#{chapter}:#{verse}"
end
