defmodule Bezalel.Study.Format do
  @moduledoc """
  The Markdown the study tools return, shared between them: verses, lexicon
  entries, and small helpers with Python's semantics where the output
  depends on them (`truncate/3` counts code points, `title/1` is
  `str.title()`).

  Ported from studybible-mcp's `tools.py` (MIT): `format_verse`,
  `_verse_heading`, `verse_english`, `bsb_label`, `format_lexicon_entry`,
  `_truncate`, `_parse_json_field`. A missing (`None`) field prints as
  nothing here, where Python printed "None".
  """

  alias Bezalel.Study.Patterns

  # Marks STEPBible's word-by-word gloss where a response labelled BSB has
  # no BSB text for a verse.
  @gloss_mark "[gloss]"

  @doc "`text` cut to `limit` code points, with `suffix` when cut."
  @spec truncate(String.t(), non_neg_integer(), String.t()) :: String.t()
  def truncate(text, limit, suffix \\ "\n\n*[Truncated]*") do
    codepoints = String.codepoints(text)

    if length(codepoints) <= limit,
      do: text,
      else: (codepoints |> Enum.take(limit) |> Enum.join()) <> suffix
  end

  @doc """
  A JSON column's value: decoded when it is a JSON string, `default` when
  it is nil or not valid JSON. Objects decode to `[{key, value}]` in the
  stored order.
  """
  @spec json(term(), term()) :: term()
  def json(value, default \\ nil)
  def json(nil, default), do: default

  def json(value, default) when is_binary(value) do
    case JSON.decode(value, :ok, object_finish: fn pairs, acc -> {Enum.reverse(pairs), acc} end) do
      {decoded, :ok, rest} -> if String.trim(rest) == "", do: decoded, else: default
      _ -> default
    end
  end

  def json(value, _default), do: value

  @doc "Python's `str.title()`: each run of letters capitalised, the rest lower case."
  @spec title(String.t()) :: String.t()
  def title(text) do
    {chars, _} =
      text
      |> String.graphemes()
      |> Enum.map_reduce(false, fn char, in_word ->
        letter? = String.upcase(char) != String.downcase(char)

        cond do
          not letter? -> {char, false}
          in_word -> {String.downcase(char), true}
          true -> {String.upcase(char), true}
        end
      end)

    Enum.join(chars)
  end

  @doc "nil and \"\" as nothing, anything else as text."
  @spec s(term()) :: String.t()
  def s(nil), do: ""
  def s(value) when is_binary(value), do: value
  def s(value), do: to_string(value)

  @doc "Python truthiness for a column value: nil, \"\", 0 and [] are false."
  @spec present?(term()) :: boolean()
  def present?(value), do: value not in [nil, "", 0, []]

  @doc """
  A verse row's English: its BSB text, else STEPBible's gloss marked
  `[gloss]` (every row carries `text_bsb`, see `Bezalel.Study.Verses`).
  """
  @spec verse_english(map()) :: String.t()
  def verse_english(%{"text_bsb" => bsb}) when bsb not in [nil, ""], do: bsb

  def verse_english(row) do
    gloss = s(row["text_english"])

    if Map.has_key?(row, "text_bsb"),
      do: String.trim_trailing("#{@gloss_mark} #{gloss}"),
      else: gloss
  end

  @doc ~S'" (BSB)" for the heading of a response showing any BSB text (verse views), else "".'
  @spec bsb_label([verse_view()]) :: String.t()
  def bsb_label(views), do: if(Enum.any?(views, & &1.bsb), do: " (BSB)", else: "")

  @doc """
  A verse's heading: its reference, or for English verse 0 (a Psalm
  superscription, stored 'Psa.82.0(82.1)') 'Psa.82 superscription (Hebrew
  Psa.82.1)'.
  """
  @spec verse_heading(map()) :: String.t()
  def verse_heading(%{"verse" => 0, "reference" => reference}) do
    case Regex.run(Patterns.get(:superscription), reference) do
      [_, book, chapter, hebrew] -> "#{book}.#{chapter} superscription (Hebrew #{book}.#{hebrew})"
      [_, book, chapter] -> "#{book}.#{chapter} superscription"
      nil -> reference
    end
  end

  def verse_heading(%{"reference" => reference}), do: reference

  @typedoc "A word of a verse: original script, Strong's number, gloss, parsing code."
  @type word :: %{
          word: String.t(),
          strongs: String.t(),
          gloss: String.t(),
          morph: String.t(),
          transliteration: String.t()
        }

  @typedoc """
  A verse as the tools return it: `heading` is the reference as shown
  (a superscription labelled), `english` the BSB (or the marked gloss),
  `bsb` whether it is the BSB, `words` the word-by-word data.
  """
  @type verse_view :: %{
          reference: String.t(),
          heading: String.t(),
          book: String.t(),
          chapter: integer(),
          verse: integer(),
          english: String.t(),
          bsb: boolean(),
          original: String.t(),
          words: [word()]
        }

  @doc "A verse row (with `text_bsb`) as a `t:verse_view/0`."
  @spec verse_view(map()) :: verse_view()
  def verse_view(row) do
    words =
      case json(row["word_data"]) do
        words when is_list(words) ->
          for word <- words, is_list(word) do
            word = Map.new(word)

            %{
              word: s(word["word"]),
              strongs: s(word["strongs"]),
              gloss: s(word["gloss"]),
              morph: s(word["morph"]),
              transliteration: s(word["transliteration"])
            }
          end

        _ ->
          []
      end

    %{
      reference: row["reference"],
      heading: verse_heading(row),
      book: row["book"],
      chapter: row["chapter"],
      verse: row["verse"],
      english: verse_english(row),
      bsb: present?(row["text_bsb"]),
      original: s(row["text_original"]),
      words: words
    }
  end

  @doc """
  A verse as Markdown: heading, English, the original text (unless
  `include_original` is false) and, when `include_words`, the word list
  with Strong's numbers and glosses (and parsing codes when
  `include_morphology`).
  """
  @spec verse(verse_view(), keyword()) :: String.t()
  def verse(view, opts \\ []) do
    include_original = Keyword.get(opts, :include_original, true)
    include_morphology = Keyword.get(opts, :include_morphology, false)
    include_words = Keyword.get(opts, :include_words, true)

    original =
      if include_original and view.original != "",
        do: ["### Original Text", view.original, ""],
        else: []

    word_lines =
      if view.words != [] and include_original and include_words,
        do:
          ["### Word Analysis" | Enum.map(view.words, &word_line(&1, include_morphology))] ++ [""],
        else: []

    Enum.join(
      [
        "## #{view.heading}#{Keyword.get(opts, :heading_note, "")}",
        "",
        if(view.english == "", do: "No English text available.", else: view.english),
        ""
      ] ++ original ++ word_lines,
      "\n"
    )
  end

  defp word_line(w, include_morphology) do
    line = "- **#{w.word}** (#{w.strongs}): #{w.gloss}"
    if include_morphology and w.morph != "", do: line <> " [#{w.morph}]", else: line
  end

  @doc "A lexicon entry as Markdown, as `word_study` shows it."
  @spec lexicon_entry(map()) :: String.t()
  def lexicon_entry(entry) do
    Enum.join(
      header(entry) ++
        definitions(entry) ++
        etymology(entry) ++
        semantic_range(entry) ++
        usage(entry) ++
        related(entry) ++
        abbott_smith(entry) ++ lxx(entry) ++ synonyms(entry) ++ nt_usage(entry),
      "\n"
    )
  end

  defp header(entry) do
    [
      "## #{entry["strongs"]} - #{s(entry["word"])}",
      "**Transliteration**: #{s(entry["transliteration"])}"
    ] ++
      if(present?(entry["pronunciation"]),
        do: ["**Pronunciation**: #{entry["pronunciation"]}"],
        else: []
      ) ++ ["**Language**: #{title(s(entry["language"]))}", ""]
  end

  defp definitions(entry) do
    short = s(entry["short_definition"])
    full = s(entry["full_definition"])

    cond do
      short != "" and full != "" and short != full ->
        label = full_label(entry["language"])

        [
          "### Brief Definition",
          short,
          "",
          "### #{label}",
          truncate(
            full,
            3000,
            "\n\n*[Definition truncated — full entry available in the lexicon]*"
          ),
          ""
        ]

      full != "" ->
        ["### Definition", truncate(full, 3000, "\n\n*[Definition truncated]*"), ""]

      short != "" ->
        ["### Definition", short, ""]

      true ->
        ["### Definition", "No definition available.", ""]
    end
  end

  defp full_label("greek"), do: "Full LSJ Definition"
  defp full_label("hebrew"), do: "Full BDB Definition"
  defp full_label(_language), do: "Full Definition"

  defp etymology(entry) do
    if present?(entry["etymology"]), do: ["### Etymology", entry["etymology"], ""], else: []
  end

  defp semantic_range(entry) do
    case json(entry["semantic_domain"]) do
      [_ | _] = domains -> ["### Semantic Range", Enum.map_join(domains, ", ", &s/1), ""]
      _ -> []
    end
  end

  defp usage(entry) do
    if present?(entry["usage_count"]),
      do: ["**Usage**: Occurs #{entry["usage_count"]} times in the Bible", ""],
      else: []
  end

  defp related(entry) do
    case json(entry["related_words"]) do
      [_ | _] = related ->
        lines =
          Enum.map(related, fn
            word when is_list(word) ->
              word = Map.new(word)
              "- #{s(word["strongs"])} #{s(word["word"])} - #{s(word["gloss"])}"

            other ->
              "- #{s(other)}"
          end)

        ["### Related Words" | lines] ++ [""]

      _ ->
        []
    end
  end

  defp abbott_smith(entry) do
    if present?(entry["abbott_smith_def"]) do
      [
        "### Abbott-Smith Definition (NT-Focused)",
        truncate(
          entry["abbott_smith_def"],
          3000,
          "\n\n*[Definition truncated — full entry available in Abbott-Smith]*"
        ),
        ""
      ]
    else
      []
    end
  end

  defp lxx(entry) do
    case json(entry["lxx_hebrew"]) do
      [_ | _] = items ->
        lines =
          for item <- items, is_list(item) do
            item = Map.new(item)
            "- #{s(item["strongs"])} #{s(item["hebrew"])}"
          end

        ["### LXX / Hebrew Equivalents" | lines] ++ [""]

      _ ->
        []
    end
  end

  defp synonyms(entry) do
    if present?(entry["synonyms"]), do: ["### Synonyms", entry["synonyms"], ""], else: []
  end

  defp nt_usage(entry) do
    if present?(entry["nt_occurrences"]),
      do: ["**NT Usage**: Occurs #{entry["nt_occurrences"]} times in the New Testament", ""],
      else: []
  end
end
