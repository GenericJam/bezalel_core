defmodule Bezalel.Study.Syntax do
  @moduledoc """
  How a verse is put together, from the `syntax` pack (built by `data/`'s
  `mix bezalel.data.syntax` from Clear-Bible MACULA's syntax trees: MACULA
  Hebrew's of the Westminster Leningrad Codex, MACULA Greek's of the SBL
  Greek New Testament; CC BY 4.0): the clauses of the sentences that touch
  the verse, each clause's rule (`PP-V-S-O`) and parts with the role they
  fill (subject, verb, object…) and their words and glosses (the pack
  also stores each word's Strong's number and lemma; the section doesn't
  show them). A clause inside a clause is listed under it; the part of a
  sentence outside the verse is marked with its verse.

  `lookup_verse` shows it with the original text, for a single verse or a
  passage with `include_morphology`; without the pack it shows nothing. The trees are
  built on the WLC and the SBLGNT, whose words can differ from the core
  pack's (STEPBible's) Hebrew and Greek, and the section says which.
  """

  alias Bezalel.Study.{Citation, Citations, DB, Reference}

  # The whole section's length in Unicode code points (headings, notes and
  # Source lines included); the rest is cut with a note.
  @max_chars 4000

  @roles %{
    "s" => "subject",
    "v" => "verb",
    "o" => "object",
    "o2" => "second object",
    "io" => "indirect object",
    "p" => "predicate",
    "adv" => "adverbial",
    "pp" => "prepositional phrase",
    "vc" => "linking verb",
    "aux" => "auxiliary"
  }

  @editions %{
    "WLC" => "MACULA Hebrew's syntax tree of the Westminster Leningrad Codex (WLC)",
    "SBLGNT" => "MACULA Greek's syntax tree of the SBL Greek New Testament (SBLGNT)"
  }

  @typedoc """
  A verse's clause structure: `reference` in the packs' English numbering
  ('Psa.3.0'), the `edition` the tree is of ("WLC" or "SBLGNT") and its
  `language`, `source_reference` the edition's own verse(s) ('Psa.3.1'),
  `source_files` the tree files in `repo` at `commit`, and `sentences` as
  the pack stores them (`Bezalel.Data.Syntax`): `%{"c" => clauses, "x" =>
  clauses outside the verse left out, "v" => the sentence's span, "r" =>
  the edition's verse number, "w" => the English verses it is split
  between}`, a clause `[depth, role, rule, parts]`, a
  part `[role, items]`, an item `[text, strong, gloss, lemma]`, `[verse,
  text]` (words outside the verse), `[verse]` (a clause outside it) or the
  number of a clause shown.
  """
  @type verse :: %{
          reference: String.t(),
          book: String.t(),
          chapter: integer(),
          verse: integer(),
          edition: String.t(),
          language: String.t(),
          source_reference: String.t(),
          source_files: [String.t()],
          repo: String.t(),
          commit: String.t(),
          sentences: [map()]
        }

  @doc """
  The clause structure of `book`'s verses at `places` (`{chapter, verse}`,
  English numbering), in that order; [] for a verse the pack lacks, and for
  all when the pack isn't on the device or can't be read.
  """
  @spec verses(String.t(), [{integer(), integer()}]) :: [verse()]
  def verses(_book, []), do: []

  def verses(book, places) do
    references = places |> Enum.uniq() |> Enum.map(fn {c, v} -> "#{book}.#{c}.#{v}" end)

    case DB.with_pack(:syntax, &read(&1, references)) do
      {:ok, {:ok, verses}} -> verses
      _missing_or_damaged -> []
    end
  end

  defp read(conn, references) do
    with :ok <- DB.check_tables(conn, :syntax, ~w(syntax_editions syntax_verses)) do
      order = references |> Enum.with_index() |> Map.new()

      verses =
        conn
        |> DB.all(
          """
          SELECT v.reference, v.book, v.chapter, v.verse, v.edition, v.source_reference,
                 v.source_files, v.clauses, e.language, e.repo, e.commit_sha
          FROM syntax_verses v JOIN syntax_editions e ON e.edition = v.edition
          WHERE v.reference IN (#{DB.placeholders(references)})
          """,
          references
        )
        |> Enum.flat_map(&verse/1)
        |> Enum.sort_by(&order[&1.reference])

      {:ok, verses}
    end
  end

  defp verse(row) do
    case JSON.decode(row["clauses"]) do
      {:ok, sentences} when is_list(sentences) ->
        [
          %{
            reference: row["reference"],
            book: row["book"],
            chapter: row["chapter"],
            verse: row["verse"],
            edition: row["edition"],
            language: row["language"],
            source_reference: row["source_reference"],
            source_files: String.split(row["source_files"]),
            repo: row["repo"],
            commit: row["commit_sha"],
            sentences: sentences
          }
        ]

      _damaged ->
        []
    end
  end

  @doc "A role code in plain English ('s' → 'subject'); an unknown code as it is."
  @spec role(String.t()) :: String.t()
  def role(code), do: Map.get(@roles, code, code)

  @doc """
  The sources of `render/1`'s section for `verses`: the tree file(s) in
  MACULA at the pinned commit of each verse it shows (not of those the
  length cap left out).
  """
  @spec citations([verse()]) :: [Citation.t()]
  def citations(verses), do: verses |> layout() |> elem(1) |> Enum.flat_map(&verse_citations/1)

  defp verse_citations(verse) do
    Enum.map(verse.source_files, &Citations.macula(verse.reference, verse.repo, verse.commit, &1))
  end

  @doc """
  The "Clause structure" section for `verses` (none for []): each verse's
  lines under its heading, with its Source line. The whole section is at
  most #{@max_chars} Unicode code points; it is cut at a whole line, the
  verses after the cut are left out, and a note says how many lines.
  """
  @spec render([verse()]) :: String.t()
  def render(verses), do: verses |> layout() |> elem(0)

  @doc "The length `render/1` caps, in Unicode code points."
  @spec max_chars() :: pos_integer()
  def max_chars, do: @max_chars

  # The section and the verses it shows.
  defp layout([]), do: {"", []}

  defp layout([first | _] = verses) do
    header = "\n\n---\n### Clause structure\n*#{intro(first)}*"
    budget = @max_chars - size(header) - size(cut_note(@max_chars))

    {blocks, _left, cut} =
      Enum.reduce(verses, {[], budget, 0}, fn verse, {blocks, left, cut} ->
        lines = verse_lines(verse)
        {block, left} = block(verse, lines, left)
        shown = if block, do: block.lines, else: 0

        {if(block, do: [{verse, block.text} | blocks], else: blocks), left,
         cut + length(lines) - shown}
      end)

    blocks = Enum.reverse(blocks)
    note = if cut > 0, do: cut_note(cut), else: ""
    text = header <> Enum.map_join(blocks, &("\n\n" <> elem(&1, 1))) <> note
    {text, Enum.map(blocks, &elem(&1, 0))}
  end

  # A verse's block, `%{text, lines}`, or nil when not one of its lines
  # fits, and the room left: its heading, the lines that fit in `left`
  # with the heading and Source line counted, its Source line. Once a verse
  # is cut, no room is left for the next.
  defp block(verse, lines, left) do
    heading = "#### #{heading(verse)}"
    source = Citation.source_line(verse_citations(verse))
    fixed = size("\n\n" <> heading <> "\n" <> source)
    {kept, taken} = take_lines(lines, left - fixed)

    cond do
      kept == [] ->
        {nil, 0}

      length(kept) < length(lines) ->
        {%{text: assemble(heading, kept, source), lines: length(kept)}, 0}

      true ->
        {%{text: assemble(heading, kept, source), lines: length(kept)}, left - fixed - taken}
    end
  end

  defp assemble(heading, lines, source), do: Enum.join([heading | lines] ++ [source], "\n")

  # The lines that fit in `room` code points, each with its line break, and
  # the room they take.
  defp take_lines(lines, room) do
    {kept, taken} =
      Enum.reduce_while(lines, {[], 0}, fn line, {kept, taken} ->
        line_size = size(line) + 1

        if taken + line_size <= room,
          do: {:cont, {[line | kept], taken + line_size}},
          else: {:halt, {kept, taken}}
      end)

    {Enum.reverse(kept), taken}
  end

  defp cut_note(cut) do
    "\n\n*Cut to keep this short: #{cut} more line#{if cut == 1, do: "", else: "s"} " <>
      "not shown; look up one verse at a time for the rest.*"
  end

  defp size(text), do: text |> String.to_charlist() |> length()

  defp intro(%{edition: edition, language: language}) do
    "From #{Map.get(@editions, edition, edition)}, whose wording can differ from the " <>
      "#{language} text above. Roles in brackets; glosses are MACULA's word glosses, " <>
      "not a translation; a clause inside another is indented under it."
  end

  defp heading(verse) do
    name = Reference.book_name(verse.book) || verse.book

    if verse.verse == 0,
      do: "#{name} #{verse.chapter} (superscription)",
      else: "#{name} #{verse.chapter}:#{verse.verse}"
  end

  # A verse's lines: per sentence, a note on its span or numbering, then
  # its clauses (numbered within the sentence).
  defp verse_lines(verse) do
    several = match?([_, _ | _], verse.sentences)

    verse.sentences
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {sentence, index} -> sentence_lines(sentence, index, several, verse) end)
  end

  defp sentence_lines(sentence, index, several, verse) do
    notes =
      [
        if(several, do: "Sentence #{index}."),
        numbering_note(sentence, verse),
        sentence["v"] && span_note(sentence)
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    clauses = sentence["c"] || []
    places = places(clauses)

    header = if notes == [], do: [], else: ["*" <> Enum.join(notes, " ") <> "*"]

    header ++
      (clauses
       |> Enum.with_index(1)
       |> Enum.map(fn {clause, number} -> clause_line(clause, number, places[number]) end))
  end

  # Clause number → the role of the part of its parent it sits in.
  defp places(clauses) do
    for [_, _, _, parts] when is_list(parts) <- clauses,
        [role, items] <- parts,
        is_list(items),
        number <- items,
        is_integer(number),
        into: %{},
        do: {number, role}
  end

  # The edition's own verse number ("r") and, when the core pack splits that
  # verse between English verses ("w"), that it is shown whole under each.
  defp numbering_note(%{"w" => covered} = sentence, verse) do
    own = sentence["r"] || "#{verse.chapter}:#{verse.verse}"
    "#{verse.edition} #{own} is split between #{covered} in English numbering; it is shown whole."
  end

  defp numbering_note(%{"r" => own}, verse), do: "#{verse.edition} numbers this verse #{own}."
  defp numbering_note(_sentence, _verse), do: nil

  defp span_note(%{"v" => span} = sentence) do
    case Map.get(sentence, "x", 0) do
      0 ->
        "The sentence runs #{span}; its words outside this verse are in ⟨ ⟩."

      left ->
        "The sentence runs #{span}; its words outside this verse are in ⟨ ⟩, and #{left} of its clauses outside it are left out."
    end
  end

  defp clause_line([depth, role, rule, parts], number, place) when is_list(parts) do
    indent = String.duplicate("  ", depth)
    body = parts |> Enum.map(&part/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" · ")
    "#{indent}#{number}. #{clause_label(role, rule, parts, place)}: #{body}"
  end

  defp clause_line(_malformed, number, _place), do: "#{number}. (unreadable clause)"

  # A clause with a role of its own is named by it ("Object clause"); one
  # without, inside a part of another clause, by that part ("Clause in the
  # subject": a relative clause in the subject is not the subject).
  # "Joined clauses" for a group of clauses with nothing but conjunctions
  # between them; "Outside a clause" for words MACULA puts in none.
  defp clause_label(role, rule, parts, place) do
    labelled = Enum.any?(parts, &match?([part_role, _] when part_role != nil, &1))
    joins = for [_, items] <- parts, item <- items, is_integer(item), reduce: 0, do: (n -> n + 1)

    name =
      cond do
        not labelled and joins >= 2 -> "Joined clauses"
        not labelled and rule == nil and joins == 0 -> "Outside a clause"
        true -> clause_name(role, place)
      end

    if rule, do: "#{name} (#{rule})", else: name
  end

  defp clause_name(nil, nil), do: "Clause"
  defp clause_name(nil, place), do: "Clause in the #{role(place)}"
  defp clause_name(role, _place), do: String.capitalize(role(role)) <> " clause"

  defp part([role, items]) do
    text = items(items)

    cond do
      text == "" -> ""
      role == nil -> text
      true -> "[#{role(role)}] #{text}"
    end
  end

  defp part(_malformed), do: ""

  # Consecutive words of the verse as one run: their text, then their
  # glosses; a clause shown as its number; text outside the verse in ⟨ ⟩.
  defp items(items) do
    items
    |> Enum.chunk_by(&word?/1)
    |> Enum.flat_map(fn [first | _] = run ->
      if word?(first), do: [words(run)], else: Enum.map(run, &other/1)
    end)
    |> Enum.join(" ")
  end

  defp word?([_text, _strong, _gloss, _lemma]), do: true
  defp word?(_item), do: false

  defp words(words) do
    text = words |> Enum.map_join(fn [text | _] -> text || "" end) |> String.trim()

    glosses =
      for [_, _, gloss, _] <- words, is_binary(gloss), gloss not in ["", "-"], do: gloss

    if glosses == [], do: text, else: "#{text} '#{Enum.join(glosses, " ")}'"
  end

  defp other(number) when is_integer(number), do: "(clause #{number})"
  defp other([label, text]), do: "⟨#{label}: #{text}⟩"
  defp other([label]), do: "(a clause in #{label})"
  defp other(_unknown), do: ""
end
