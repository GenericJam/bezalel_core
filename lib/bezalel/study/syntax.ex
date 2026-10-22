defmodule Bezalel.Study.Syntax do
  @moduledoc """
  How a verse is put together, from the `syntax` pack (built by `data/`'s
  `mix bezalel.data.syntax` from Clear-Bible MACULA's syntax trees: MACULA
  Hebrew's of the Westminster Leningrad Codex, MACULA Greek's of the SBL
  Greek New Testament; CC BY 4.0): the clauses of the sentences that touch
  the verse, each clause's rule (`PP-V-S-O`) and parts with the role they
  fill (subject, verb, object…) and their words, glosses and Strong's
  numbers. A clause inside a clause is listed under it; the part of a
  sentence outside the verse is marked with its verse.

  `lookup_verse` shows it for a single verse, or a passage with
  `include_morphology`; without the pack it shows nothing. The trees are
  built on the WLC and the SBLGNT, whose words can differ from the core
  pack's (STEPBible's) Hebrew and Greek, and the section says which.
  """

  alias Bezalel.Study.{Citation, Citations, DB, Reference}

  # The section's length; the rest is cut with a note.
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

  @doc "The sources of `verses`: each verse's tree file(s) in MACULA at the pinned commit."
  @spec citations([verse()]) :: [Citation.t()]
  def citations(verses), do: Enum.flat_map(verses, &verse_citations/1)

  defp verse_citations(verse) do
    Enum.map(verse.source_files, &Citations.macula(verse.reference, verse.repo, verse.commit, &1))
  end

  @doc """
  The "Clause structure" section for `verses` (none for []), at most
  #{@max_chars} characters of clause lines, with a note when cut; each
  verse's lines under its heading, with its Source line.
  """
  @spec render([verse()]) :: String.t()
  def render([]), do: ""

  def render([first | _] = verses) do
    {blocks, _used, cut} =
      Enum.reduce(verses, {[], 0, 0}, fn verse, {blocks, used, cut} ->
        lines = verse_lines(verse)
        {kept, used} = take_lines(lines, used)
        {[block(verse, kept) | blocks], used, cut + length(lines) - length(kept)}
      end)

    note =
      if cut > 0,
        do:
          "\n\n*Cut to keep this short: #{cut} more line#{if cut == 1, do: "", else: "s"} " <>
            "not shown; look up one verse at a time for the rest.*",
        else: ""

    "\n\n---\n### Clause structure\n*#{intro(first)}*\n\n" <>
      (blocks |> Enum.reverse() |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")) <> note
  end

  defp block(_verse, []), do: nil

  defp block(verse, lines) do
    "#### #{heading(verse)}\n" <>
      Enum.join(lines, "\n") <> "\n" <> Citation.source_line(verse_citations(verse))
  end

  # The lines that fit in what is left of @max_chars, in order.
  defp take_lines(lines, used) do
    Enum.reduce_while(lines, {[], used}, fn line, {kept, used} ->
      size = String.length(line) + 1

      if used + size <= @max_chars,
        do: {:cont, {[line | kept], used + size}},
        else: {:halt, {kept, @max_chars}}
    end)
    |> then(fn {kept, used} -> {Enum.reverse(kept), used} end)
  end

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

    header = if notes == [], do: [], else: ["*" <> Enum.join(notes, " ") <> "*"]

    header ++
      (clauses
       |> Enum.with_index(1)
       |> Enum.map(fn {clause, number} -> clause_line(clause, number) end))
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

  defp clause_line([depth, role, rule, parts], number) when is_list(parts) do
    indent = String.duplicate("  ", depth)
    body = parts |> Enum.map(&part/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" · ")
    "#{indent}#{number}. #{clause_label(role, rule, parts)}: #{body}"
  end

  defp clause_line(_malformed, number), do: "#{number}. (unreadable clause)"

  # "Joined clauses" for a group of clauses with nothing but conjunctions
  # between them; "Outside a clause" for words MACULA puts in none.
  defp clause_label(role, rule, parts) do
    labelled = Enum.any?(parts, fn [part_role, _] -> part_role != nil end)
    joins = for [_, items] <- parts, item <- items, is_integer(item), reduce: 0, do: (n -> n + 1)

    name =
      cond do
        labelled -> clause_name(role)
        joins >= 2 -> "Joined clauses"
        rule == nil and joins == 0 -> "Outside a clause"
        true -> clause_name(role)
      end

    if rule, do: "#{name} (#{rule})", else: name
  end

  defp clause_name(nil), do: "Clause"
  defp clause_name(role), do: String.capitalize(role(role)) <> " clause"

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
