defmodule Bezalel.Study.Dictionaries do
  @moduledoc """
  The UBS dictionaries in the optional `dictionaries` pack (built by
  `data/`'s `mix bezalel.data.dictionaries`): the UBS Dictionary of
  Biblical Hebrew (from the Semantic Dictionary of Biblical Hebrew) and the
  UBS Dictionary of the Greek New Testament (from Louw & Nida), CC BY-SA
  4.0. `word_study` shows a Strong's number's entries after the core
  lexicon's: each meaning with its semantic domains, Louw–Nida number,
  definition and glosses (`section/1`).

  The pack keys each entry by the core lexicon's Strong's numbers (an
  Aramaic `A2452` is `H2452`). Without the pack, or with a damaged one,
  `entries/1` is empty and `word_study` reads as it did without it.
  """

  alias Bezalel.Study.{Citation, Citations, DB, Patterns}

  @tables ~w(dictionaries dictionary_entries dictionary_strongs dictionary_meanings
             dictionary_domains dictionary_meaning_domains)

  # What one entry may add to word_study: its first meanings, cut at about
  # the length `Format.lexicon_entry/1` gives a full definition.
  @max_entries 3
  @max_meanings 10
  @max_chars 3000
  @max_comment 300

  @typedoc "A domain of a meaning: `kind` `domain` or `subdomain`; `source` the domain it is seen from (SDBH)."
  @type domain :: %{
          kind: String.t(),
          code: String.t(),
          name: String.t(),
          source: String.t() | nil
        }

  @type meaning :: %{
          position: pos_integer(),
          part_of_speech: String.t() | nil,
          louw_nida: String.t() | nil,
          definition: String.t() | nil,
          glosses: [String.t()],
          comments: String.t() | nil,
          reference_count: non_neg_integer(),
          domains: [domain()]
        }

  @typedoc "An entry: `dictionary` its key (`ubs_hebrew`, `ubs_greek`), `codes` the Strong's codes it gives for the number looked up."
  @type entry :: %{
          dictionary: String.t(),
          title: String.t(),
          lemma: String.t(),
          codes: String.t(),
          meanings: [meaning()]
        }

  @doc """
  The entries for a Strong's number (`H7307`; a sense suffix, `H7307G`, is
  dropped, as the core lexicon keys the bare number), in the
  dictionary's order; at most #{@max_entries}, and `more` how many
  others there are. Empty when the pack is missing or damaged, or `strongs`
  isn't a Strong's number.
  """
  @spec entries(String.t() | nil) :: %{entries: [entry()], more: non_neg_integer()}
  def entries(strongs) do
    with true <- is_binary(strongs),
         [_, letter, number, _suffix] <- Regex.run(Patterns.get(:strongs), String.upcase(strongs)),
         key = letter <> String.pad_leading(Integer.to_string(String.to_integer(number)), 4, "0"),
         {:ok, {:ok, found}} <- DB.with_pack(:dictionaries, &read(&1, key)) do
      found
    else
      _none -> %{entries: [], more: 0}
    end
  end

  defp read(conn, key) do
    with :ok <- DB.check_tables(conn, :dictionaries, @tables) do
      rows =
        DB.all(
          conn,
          """
          SELECT s.dictionary, s.entry_id, s.given, e.lemma, d.title
          FROM dictionary_strongs s
          JOIN dictionary_entries e ON e.dictionary = s.dictionary AND e.entry_id = s.entry_id
          JOIN dictionaries d ON d.key = s.dictionary
          WHERE s.strongs = ?
          ORDER BY s.dictionary, s.entry_id
          """,
          [key]
        )

      shown = Enum.take(rows, @max_entries)

      {:ok, %{entries: Enum.map(shown, &entry(conn, &1)), more: length(rows) - length(shown)}}
    end
  end

  defp entry(conn, row) do
    args = [row["dictionary"], row["entry_id"]]

    domains =
      conn
      |> DB.all(
        """
        SELECT md.meaning_id, md.kind, md.code, n.name, s.name AS source
        FROM dictionary_meaning_domains md
        JOIN dictionary_domains n ON n.dictionary = md.dictionary AND n.code = md.code
        LEFT JOIN dictionary_domains s ON s.dictionary = md.dictionary AND s.code = md.source_code
        WHERE md.dictionary = ? AND md.meaning_id IN
          (SELECT meaning_id FROM dictionary_meanings WHERE dictionary = ? AND entry_id = ?)
        ORDER BY md.meaning_id, md.kind, md.position
        """,
        [row["dictionary"] | args]
      )
      |> Enum.group_by(
        & &1["meaning_id"],
        &%{kind: &1["kind"], code: &1["code"], name: &1["name"], source: &1["source"]}
      )

    meanings =
      conn
      |> DB.all(
        "SELECT * FROM dictionary_meanings WHERE dictionary = ? AND entry_id = ? ORDER BY position",
        args
      )
      |> Enum.map(fn m ->
        %{
          position: m["position"],
          part_of_speech: m["part_of_speech"],
          louw_nida: m["louw_nida"],
          definition: m["definition"],
          glosses: JSON.decode!(m["glosses"]),
          comments: m["comments"],
          reference_count: m["reference_count"],
          domains: Map.get(domains, m["meaning_id"], [])
        }
      end)

    %{
      dictionary: row["dictionary"],
      title: row["title"],
      lemma: row["lemma"],
      codes: row["given"],
      meanings: meanings
    }
  end

  @doc "The entry's source: the dictionary's file at the pack's commit (`Citations.ubs_dictionary/3`)."
  @spec citation(entry()) :: Citation.t()
  def citation(entry), do: Citations.ubs_dictionary(entry.dictionary, entry.lemma, entry.codes)

  @doc """
  The Markdown `word_study` appends for `found` (`entries/1`): each entry's
  meanings with their domains, at most #{@max_meanings} and about
  #{@max_chars} characters an entry (saying how many are left out), each
  entry's Source line, and how many entries aren't shown. Empty for none.
  """
  @spec section(%{entries: [entry()], more: non_neg_integer()}) :: String.t()
  def section(%{entries: []}), do: ""

  def section(%{entries: entries, more: more}) do
    Enum.map_join(entries, &entry_text/1) <>
      if more > 0,
        do:
          "\n*[#{more} more UBS dictionary #{plural(more, "entry", "entries")} for this number not shown]*\n",
        else: ""
  end

  defp entry_text(entry) do
    pos = entry.meanings |> Enum.map(& &1.part_of_speech) |> Enum.uniq()
    shared_pos = match?([p] when is_binary(p), pos)
    header_pos = if shared_pos, do: " — *#{hd(pos)}*", else: ""

    {lines, shown} =
      entry.meanings
      |> Enum.take(@max_meanings)
      |> Enum.reduce_while({[], 0}, fn meaning, {lines, n} ->
        line = meaning_line(meaning, n + 1, shared_pos)
        used = lines |> Enum.map(&String.length/1) |> Enum.sum()

        if n > 0 and used + String.length(line) > @max_chars,
          do: {:halt, {lines, n}},
          else: {:cont, {lines ++ [line], n + 1}}
      end)

    total = length(entry.meanings)

    cut =
      if shown < total,
        do: "*[#{shown} of #{total} meanings shown; the rest are in the UBS entry]*\n",
        else: ""

    "\n## #{entry.title}: #{entry.lemma} (#{entry.codes})#{header_pos}\n" <>
      Enum.join(lines) <> cut <> Citation.source_line(citation(entry)) <> "\n"
  end

  defp meaning_line(meaning, n, shared_pos) do
    pos =
      if shared_pos or is_nil(meaning.part_of_speech),
        do: "",
        else: "*#{meaning.part_of_speech}* · "

    ln = if meaning.louw_nida, do: "LN #{meaning.louw_nida} · ", else: ""

    glosses =
      if meaning.glosses == [], do: "", else: "Glosses: #{Enum.join(meaning.glosses, "; ")} · "

    count = meaning.reference_count

    comments =
      case meaning.comments do
        nil -> ""
        text -> "\n   Note: " <> truncate(text, @max_comment)
      end

    "#{n}. #{pos}#{ln}**#{domains(meaning.domains)}** — #{meaning.definition || "(no definition)"}" <>
      "\n   #{glosses}#{count} #{plural(count, "reference", "references")}" <> comments <> "\n"
  end

  # SDBH: "Spirits (source domain: Deities)"; Louw–Nida: "Attitudes and Emotions › Love, …".
  defp domains([]), do: "no domain"

  defp domains(domains) do
    {main, sub} = Enum.split_with(domains, &(&1.kind == "domain"))

    main_text =
      Enum.map_join(main, "; ", fn d ->
        if d.source, do: "#{d.name} (source domain: #{d.source})", else: d.name
      end)

    case sub do
      [] -> main_text
      _ -> main_text <> " › " <> Enum.map_join(sub, "; ", & &1.name)
    end
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many
end
