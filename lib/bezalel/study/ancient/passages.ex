defmodule Bezalel.Study.Ancient.Passages do
  @moduledoc """
  Ancient-source passages as the two ancient tools show them: search folding,
  match-centred excerpts, line windows, typed biblical links and ⚠ notes,
  caveats, tiers and sources.

  Ported from studybible-mcp's `tools.py` (`_fold_with_positions`,
  `_match_excerpt`, `_ancient_passage_lines`, `_closing_block`, …) and
  `database.py` (`fold_ancient_search_text`, `_attach_ancient_annotations`)
  (MIT). Case folding is `String.downcase/1` plus the full case folds of
  Python's `casefold` that matter here (final sigma, ß, Greek symbol forms).
  """

  alias Bezalel.Study.{Ancient, DB, Patterns}

  @english_excerpt 1500
  @original_excerpt 600
  @full_english 8000
  @full_original 3000
  @response_budget 12_000
  @line_context 2
  @hebrew_prefix_letters "ובהלמכש"

  @type passage :: map()

  def line_context, do: @line_context

  @doc "Excerpt limits: `{english, original}`."
  def limits(true), do: {@full_english, @full_original}
  def limits(false), do: {@english_excerpt, @original_excerpt}

  # --- Folding --------------------------------------------------------------

  @casefold %{
    "ς" => "σ",
    "ß" => "ss",
    "ſ" => "s",
    "ϐ" => "β",
    "ϑ" => "θ",
    "ϕ" => "φ",
    "ϖ" => "π",
    "ϰ" => "κ",
    "ϱ" => "ρ",
    "ϵ" => "ε",
    "ﬀ" => "ff",
    "ﬁ" => "fi",
    "ﬂ" => "fl",
    "ﬃ" => "ffi",
    "ﬄ" => "ffl",
    "ﬅ" => "st",
    "ﬆ" => "st"
  }

  @doc "Python's `str.casefold` for the scripts the corpora use."
  @spec casefold(String.t()) :: String.t()
  def casefold(text) do
    text
    |> String.downcase()
    |> String.replace(Map.keys(@casefold), &Map.fetch!(@casefold, &1))
  end

  @doc "Drops nonspacing marks and format characters (NFD), then recomposes."
  @spec strip_marks(String.t()) :: String.t()
  def strip_marks(text) do
    text = text |> :unicode.characters_to_nfc_binary() |> :unicode.characters_to_nfd_binary()
    Patterns.get(:ancient_marks) |> Regex.replace(text, "") |> :unicode.characters_to_nfc_binary()
  end

  @doc "Marks and case folded as the search index folds them."
  @spec fold(String.t()) :: String.t()
  def fold(text), do: text |> strip_marks() |> casefold() |> :unicode.characters_to_nfc_binary()

  @doc "Editorial signs deleted, so a marked word reads as one word."
  @spec strip_editorial_signs(String.t()) :: String.t()
  def strip_editorial_signs(text), do: Regex.replace(Patterns.get(:editorial_signs), text, "")

  @doc "The folded search terms of a query, operators (AND OR NOT NEAR) dropped."
  @spec terms(String.t()) :: [String.t()]
  def terms(query) do
    query
    |> strip_editorial_signs()
    |> strip_marks()
    |> words()
    |> Enum.reject(&(&1 in ~w(AND OR NOT NEAR)))
    |> Enum.flat_map(&words(fold(&1)))
    |> Enum.uniq()
  end

  defp words(text), do: Patterns.get(:ancient_word) |> Regex.scan(text) |> List.flatten()

  @doc "Is `word` all Hebrew letters?"
  def hebrew?(word), do: Regex.match?(Patterns.get(:hebrew_word), word)

  # --- Excerpts -------------------------------------------------------------

  # Text folded as the index does, with each kept character's position.
  defp fold_with_positions(text) do
    text
    |> String.codepoints()
    |> Enum.with_index()
    |> Enum.flat_map(fn {ch, index} ->
      if Regex.match?(Patterns.get(:ancient_marks), ch) or strip_editorial_signs(ch) == "" do
        []
      else
        base =
          Patterns.get(:ancient_combining)
          |> Regex.replace(:unicode.characters_to_nfd_binary(ch), "")
          |> casefold()

        [{String.first(base) || ch, index}]
      end
    end)
    |> Enum.unzip()
    |> then(fn {chars, positions} -> {Enum.join(chars), positions} end)
  end

  @doc """
  Up to `limit` characters of `text` around the first query match (folded,
  stem or Hebrew prefix letters allowed), ellipses where cut.
  """
  @spec match_excerpt(String.t(), String.t(), pos_integer()) :: String.t()
  def match_excerpt(text, query, limit) do
    chars = text |> String.codepoints() |> List.to_tuple()
    size = tuple_size(chars)

    if size <= limit do
      text
    else
      start = excerpt_start(chars, match_position(text, query), limit)
      end_ = excerpt_end(chars, start, limit)
      body = chars |> Tuple.to_list() |> Enum.slice(start, end_ - start) |> Enum.join()
      "#{if start > 0, do: "…"}#{body}#{if end_ < size, do: "…"}"
    end
  end

  # The position in `text` of the earliest query word's match, or nil.
  defp match_position(text, query) do
    {folded, folded_positions} = fold_with_positions(text)
    folded_positions = List.to_tuple(folded_positions)
    {query_folded, _} = fold_with_positions(query)

    positions =
      for word <- words(query_folded),
          index = first_match(folded, word),
          index != nil,
          do: elem(folded_positions, index)

    if positions != [], do: Enum.min(positions)
  end

  # A fifth of the limit before the match, moved to the next word start if
  # one is near.
  defp excerpt_start(_chars, nil, _limit), do: 0

  defp excerpt_start(chars, position, limit) do
    case max(0, position - div(limit, 5)) do
      0 -> 0
      start -> next_word(chars, start)
    end
  end

  defp next_word(chars, start) do
    case find_space(chars, start, tuple_size(chars)) do
      space when is_integer(space) and space < start + 40 -> space + 1
      _ -> start
    end
  end

  # `limit` characters on, cut back to a word end in the excerpt's second half.
  defp excerpt_end(chars, start, limit) do
    end_ = min(tuple_size(chars), start + limit)

    with true <- end_ < tuple_size(chars),
         space when is_integer(space) and space > start + div(limit, 2) <-
           rfind_space(chars, start, end_) do
      space
    else
      _ -> end_
    end
  end

  defp first_match(folded, word) do
    length = word |> String.codepoints() |> length()

    stem =
      if length <= 5,
        do: word,
        else: word |> String.codepoints() |> Enum.take(length - 2) |> Enum.join()

    source =
      if hebrew?(word),
        do: "(?<!\\w)[#{@hebrew_prefix_letters}]{0,2}#{Regex.escape(stem)}",
        else: "\\b#{Regex.escape(stem)}"

    case Regex.run(Regex.compile!(source, "u"), folded, return: :index) do
      [{byte, _}] -> folded |> binary_part(0, byte) |> String.codepoints() |> length()
      nil -> nil
    end
  end

  defp find_space(chars, from, size),
    do: Enum.find(from..(size - 1)//1, &(elem(chars, &1) == " "))

  defp rfind_space(chars, from, to),
    do: Enum.find((to - 1)..from//-1, &(elem(chars, &1) == " "))

  defp excerpt(text, query, limit, note_cut) do
    excerpt = match_excerpt(text, query, limit)
    size = text |> String.codepoints() |> length()

    if note_cut and size > limit,
      do: excerpt <> " *[excerpt of #{thousands(size)} characters; full_text=true shows more]*",
      else: excerpt
  end

  defp thousands(n) when n < 1000, do: Integer.to_string(n)

  defp thousands(n),
    do:
      thousands(div(n, 1000)) <>
        "," <> String.pad_leading(Integer.to_string(rem(n, 1000)), 3, "0")

  # --- Line windows ---------------------------------------------------------

  @doc """
  For a line-numbered corpus, the cited lines ±#{@line_context} as a sort-key
  window (nil for a whole-column citation or another corpus).
  """
  @spec window(Ancient.corpus(), Ancient.work(), integer(), integer()) ::
          {integer(), integer()} | nil
  def window(corpus, work, start, end_) do
    scale = work.locator.scale

    cond do
      not corpus.line_numbered -> nil
      rem(start, scale) == 0 and rem(end_, scale) == scale - 1 -> nil
      true -> {start - @line_context, end_ + @line_context}
    end
  end

  defp splitlines(text) do
    lines = Regex.split(Patterns.get(:line_breaks), text)
    if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
  end

  # The original cut to the lines inside `window`, and a note naming them.
  defp line_window(row, window) do
    corpus = Ancient.corpus(row["corpus"] || "")
    work = corpus && Ancient.work(corpus, row["work_key"])

    if window == nil or corpus == nil or not corpus.line_numbered or work == nil,
      do: {row["original_text"], nil},
      else: cut_lines(row, window, work.locator.scale)
  end

  defp cut_lines(row, {low, high}, scale) do
    text = row["original_text"]
    base = row["sort_start"] - rem(row["sort_start"], scale)
    lines = splitlines(text)

    kept =
      Enum.filter(lines, fn line ->
        number = line_number(line)
        number != nil and low <= base + number and base + number <= high
      end)

    if kept == [] or length(kept) == length(lines) do
      {text, nil}
    else
      {Enum.join(kept, "\n"), lines_note(div(base, scale), kept)}
    end
  end

  defp line_number(line) do
    number = line |> String.split(" ", parts: 2) |> hd()
    if Regex.match?(Patterns.get(:ascii_digits), number), do: String.to_integer(number)
  end

  defp lines_note(column, kept) do
    first = kept |> hd() |> String.split(" ", parts: 2) |> hd()
    last = kept |> List.last() |> String.split(" ", parts: 2) |> hd()
    shown = if first == last, do: "#{column}:#{first}", else: "#{column}:#{first}–#{last}"
    "Lines #{shown} shown (the cited line ±#{@line_context}); cite the column for all of it."
  end

  # --- Passages -------------------------------------------------------------

  @doc "Attaches each row's typed biblical links and editorial notes (in the pack's order)."
  @spec annotate(DB.conn(), [DB.row()]) :: [DB.row()]
  def annotate(_conn, []), do: []

  def annotate(conn, rows) do
    ids = Enum.map(rows, & &1["id"])

    links =
      DB.all(
        conn,
        """
        SELECT passage_id, biblical_book, sort_start, sort_end, relationship_note, relation
        FROM ancient_source_biblical_links WHERE passage_id IN (#{DB.placeholders(ids)})
        ORDER BY CASE relation WHEN 'aligned' THEN 0 WHEN 'contrast' THEN 1
                 WHEN 'echo' THEN 2 ELSE 3 END, biblical_book, sort_start
        """,
        ids
      )
      |> Enum.group_by(& &1["passage_id"])

    notes =
      DB.all(
        conn,
        """
        SELECT passage_id, citation, kind, note, contrast, aligned FROM ancient_source_notes
        WHERE passage_id IN (#{DB.placeholders(ids)}) ORDER BY sort_start, id
        """,
        ids
      )
      |> Enum.group_by(& &1["passage_id"])

    Enum.map(rows, fn row ->
      row
      |> Map.put("biblical_links", Map.get(links, row["id"], []))
      |> Map.put("editorial_notes", Map.get(notes, row["id"], []))
    end)
  end

  @doc """
  A passage as data: its heading parts, tag and tiers, the English and
  original excerpts, notes, links and provenance.

  Options: `:query` (centres the excerpts), `:default_corpus`,
  `:include_original`, `:full_text`, `:note_cut`, `:window`.
  """
  @spec passage(DB.row(), keyword()) :: passage()
  def passage(row, opts) do
    default_corpus = Keyword.get(opts, :default_corpus)
    corpus = Ancient.corpus(row["corpus"] || default_corpus || "")
    language = language(row, corpus)
    {tag, tiers} = Ancient.row_tag(row, default_corpus)
    {english, original, original_only, lines_note} = texts(row, corpus, language, opts)

    %{
      id: row["id"],
      reference: row["reference"],
      author: row["author"],
      alternate_reference: present(row["alternate_reference"]),
      corpus: row["corpus"] || default_corpus,
      work_key: row["work_key"],
      work_title: row["work_title"],
      sort_start: row["sort_start"],
      sort_end: row["sort_end"],
      tag: tag,
      tiers: tiers,
      editorial_heading: present(row["editorial_heading"]),
      heading_label: if(corpus, do: corpus.heading_label, else: "Editorial heading"),
      language: language,
      english: english,
      original: original,
      original_only: original_only,
      lines_shown: lines_note,
      notes:
        Enum.map(
          row["editorial_notes"] || [],
          &Map.take(&1, ~w(citation kind note contrast aligned))
        ),
      links: Enum.map(row["biblical_links"] || [], &link/1),
      source: source(row, corpus, default_corpus, language)
    }
  end

  defp language(row, corpus) do
    cond do
      present(row["original_language"]) -> row["original_language"]
      corpus -> corpus.original_language
      true -> "Original-language"
    end
  end

  # {English excerpt, original excerpt, original-only note, lines-shown note}.
  defp texts(row, corpus, language, opts) do
    query = Keyword.get(opts, :query, "")
    note_cut = Keyword.get(opts, :note_cut, false)
    {english_limit, original_limit} = limits(Keyword.get(opts, :full_text, false))

    cond do
      present(row["text"]) ->
        original =
          if present(row["original_text"]) && Keyword.get(opts, :include_original, true),
            do: original_excerpt(row, query, original_limit, opts)

        {excerpt(row["text"], query, english_limit, note_cut), original, nil, nil}

      present(row["original_text"]) ->
        # Without English the original is the passage: centre it on the match.
        {text, shown} = line_window(row, Keyword.get(opts, :window))
        missing = if corpus, do: corpus.no_english_note, else: "No English translation included"
        original = excerpt(text, query, english_limit, note_cut)
        {nil, original, "#{missing}; #{language} only.", shown}

      true ->
        {nil, nil, nil, nil}
    end
  end

  # Beside English, the original is centred only on an original-script
  # query, and then twice as long.
  defp original_excerpt(row, query, limit, opts) do
    {text, _} = line_window(row, Keyword.get(opts, :window))

    if Regex.match?(Patterns.get(:original_script), query),
      do: excerpt(text, query, limit * 2, Keyword.get(opts, :note_cut, false)),
      else: excerpt(text, "", limit, Keyword.get(opts, :note_cut, false))
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp link(link) do
    {chapter, verse} = {div(link["sort_start"], 1000), rem(link["sort_start"], 1000)}
    {end_chapter, end_verse} = {div(link["sort_end"], 1000), rem(link["sort_end"], 1000)}

    %{
      relation: link["relation"],
      label: Ancient.relation_label(link["relation"]),
      book: link["biblical_book"],
      reference:
        Ancient.format_biblical_range(
          link["biblical_book"],
          chapter,
          verse,
          end_chapter,
          end_verse
        ),
      note: present(link["relationship_note"])
    }
  end

  defp source(row, corpus, default_corpus, language) do
    %{
      label: (corpus && corpus.label) || row["corpus"] || default_corpus || "Ancient source",
      language: language,
      edition: row["edition"],
      translation: if(present(row["text"]), do: row["translation"], else: "none included"),
      license: row["license"],
      url: row["source_url"]
    }
  end

  # --- Markdown -------------------------------------------------------------

  @doc """
  The Markdown of `passages` after `header` lines: each passage's block
  until the response budget, then the caveats, tiers and sources of the
  passages shown. `cut.(passage, shown_count)` is the line printed when the
  budget stops the list; `suffix` is appended to each heading.
  """
  @spec render(
          [String.t()],
          [passage()],
          String.t() | nil,
          (passage(), non_neg_integer() -> String.t()),
          String.t()
        ) ::
          String.t()
  def render(header, passages, default_corpus, cut, suffix \\ "") do
    {lines, shown, _seen} =
      Enum.reduce_while(passages, {header, [], MapSet.new()}, fn passage, {lines, shown, seen} ->
        {block, seen_after} = block(passage, seen, suffix)

        if shown != [] and size(lines) + size(block) > @response_budget do
          {:halt, {lines ++ [cut.(passage, length(shown)), ""], shown, seen}}
        else
          {:cont, {lines ++ block, shown ++ [passage], seen_after}}
        end
      end)

    (lines ++ closing(shown, default_corpus)) |> Enum.join("\n") |> String.trim_trailing()
  end

  # Python len: code points, not graphemes.
  defp size(lines), do: Enum.reduce(lines, 0, &(length(String.codepoints(&1)) + &2))

  defp block(p, seen, suffix) do
    {notes, seen} = notes(p, seen)

    links =
      if p.links == [], do: [], else: ["" | Enum.map(p.links, &"- #{link_line(&1)}")]

    {[heading(p, suffix), "*#{p.tag}*"] ++
       editorial_heading(p) ++ text_lines(p) ++ notes ++ links ++ ["", "---", ""], seen}
  end

  defp heading(p, suffix) do
    heading =
      if String.starts_with?(p.reference, p.author),
        do: p.reference,
        else: "#{p.author}, #{p.reference}"

    heading = if p.alternate_reference, do: "#{heading} (#{p.alternate_reference})", else: heading
    "### #{heading}#{suffix}"
  end

  defp editorial_heading(%{editorial_heading: nil}), do: []

  defp editorial_heading(p),
    do: ["*#{p.heading_label} (editorial): #{p.editorial_heading}*"]

  defp text_lines(%{english: nil, original: nil}), do: []

  defp text_lines(%{english: nil} = p) do
    ["", "*#{p.original_only}*"] ++
      if(p.lines_shown, do: ["*#{p.lines_shown}*"], else: []) ++
      ["", "**#{p.language}:** #{p.original}"]
  end

  defp text_lines(p) do
    ["", p.english] ++ if(p.original, do: ["", "**#{p.language}:** #{p.original}"], else: [])
  end

  # Each ⚠ note once per response.
  defp notes(p, seen) do
    Enum.reduce(p.notes, {[], seen}, fn note, {lines, seen} ->
      key = {note["citation"], note["kind"], note["note"]}

      if MapSet.member?(seen, key),
        do: {lines, seen},
        else: {lines ++ ["", note(note, p.reference)], MapSet.put(seen, key)}
    end)
  end

  defp link_line(%{note: nil} = link), do: "#{link.label}: #{link.reference}"

  defp link_line(link) do
    if String.starts_with?(link.note, "("),
      do: "#{link.label}: #{link.reference} #{link.note}",
      else: "#{link.label}: #{link.reference} — #{link.note}"
  end

  defp note(note, reference) do
    related =
      [{"contrast", "Contrast"}, {"aligned", "Aligned"}]
      |> Enum.filter(fn {field, _} -> present(note[field]) end)
      |> Enum.map_join("; ", fn {field, label} -> "#{label}: #{note[field]}" end)
      |> String.replace("; Aligned:", ". Aligned:")

    where = if note["citation"] == reference, do: "", else: "#{note["citation"]}: "
    "⚠ #{where}#{note["note"]}" <> if(related != "", do: " (#{related})", else: "")
  end

  defp closing(shown, default_corpus) do
    caveats =
      shown
      |> Enum.map(&(&1.corpus || default_corpus || ""))
      |> Enum.uniq()
      |> Enum.flat_map(&caveat/1)

    tiers =
      for tier <- shown |> Enum.flat_map(& &1.tiers) |> Enum.uniq() |> Enum.sort(),
          description = Ancient.tiers()[tier],
          description != nil,
          do: "- Tier #{tier}: #{description}."

    ["**Caveats**"] ++ caveats ++ tiers ++ ["", "**Sources**"] ++ sources(shown)
  end

  defp caveat(""), do: []

  defp caveat(key) do
    case Ancient.corpus(key) do
      %{caveat: caveat, label: label} when caveat != "" -> ["- #{label}: #{caveat}"]
      %{label: label} -> ["- #{label}: Not Scripture."]
      nil -> ["- #{key}: Not Scripture."]
    end
  end

  # One line per provenance, with each of its URLs once.
  defp sources(shown) do
    {order, urls} =
      Enum.reduce(shown, {[], %{}}, fn %{source: s}, {order, urls} ->
        key = {s.label, s.language, s.edition, s.translation, s.license}
        list = Map.get(urls, key, [])

        {if(Map.has_key?(urls, key), do: order, else: [key | order]),
         Map.put(urls, key, if(s.url in list, do: list, else: list ++ [s.url]))}
      end)

    for {label, language, edition, translation, license} = key <- Enum.reverse(order) do
      "- #{label}: #{language}: #{edition}. English: #{translation}. " <>
        "License: #{license_text(license)}. " <> Enum.join(urls[key], " ")
    end
  end

  @doc "The licence, with a non-commercial licence marked and linked."
  @spec license_text(String.t()) :: String.t()
  def license_text(license) do
    Regex.replace(Patterns.get(:nc_license), license, fn whole, sa, version ->
      variant = if sa != "", do: "by-nc-sa", else: "by-nc"
      "#{whole} (non-commercial; https://creativecommons.org/licenses/#{variant}/#{version}/)"
    end)
  end
end
