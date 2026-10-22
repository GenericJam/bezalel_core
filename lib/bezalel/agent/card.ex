defmodule Bezalel.Agent.Card do
  @moduledoc """
  The passage card of a live reply, built from what `lookup_verse` or
  `word_study` returned for the screens (rho's tool details, the tools'
  `result/1`): the English of each verse, with the words whose original
  the tool's word-by-word data names highlighted. A highlighted word
  carries its Strong's number, original word, transliteration, gloss and
  parsing code, so the word sheet opens without asking the pack again.

  A card is a map with string keys, stored with its message
  (`Bezalel.Library.Message`'s `card`):

      %{
        "from" => "lookup_verse",
        "title" => "Exodus 31:2-3",
        "version" => "NET",
        "version_url" => "https://netbible.org/bible/Exodus+31:2",
        "verses" => [%{"ref" => "2", "url" => "https://netbible.org/bible/Exodus+31:2",
                       "tokens" => [["See,", nil], ["called", "H7121G"], ...]}],
        "words" => %{"H7121G" => %{"strongs" => ..., "word" => ..., "translit" => ...,
                                   "gloss" => ..., "morph" => ...}},
        "more" => 0
      }

  `version` is the translation the tool quoted (the result's
  `translation`, the user's choice in Settings or the BSB standing in for
  a translation that isn't installed or lacks the book) when any verse
  shown is its text (as `Bezalel.Study.Format.translation_label/2` labels
  it), empty when every verse shown has only STEPBible's gloss. A verse
  quoted in a translation has its page there as `url`
  (`Bezalel.Study.Citations.scripture/2`: netbible.org's verse page, Bible
  Hub's for the BSB and for a verse the BSB stands in for, eBible.org's
  for the JPS, Door43's reader for the ULT and UST). A verse the BSB stands
  in for, in a card that also quotes the chosen translation (a ULT word
  study with an Ezekiel example), carries its own `"version" => "BSB"`;
  when every quoted verse shown is such a verse, the card's `version` is
  "BSB". `version_url` is set for the NET,
  whose terms ask for "(NET)" after the quotation, linked to netbible.org:
  the first verse quoted in the NET's page (a page on netbible.org, which
  the terms allow), for the host app to draw after the last verse.

  English and original aren't aligned word for word in the packs: an
  English word is highlighted when it is a content word of an original
  word's gloss in that verse ("filled" in "and/ I have filled"). A word
  the glosses don't share stays plain.
  """

  alias Bezalel.Agent.Patterns
  alias Bezalel.Study.{Citations, Reference, Translations}

  # Verses a card shows; a longer passage says how many more there are.
  @max_verses 6

  @stopwords ~w(a an the of and or to in on at by for with from as is was be been are were
                i me my mine you your he him his she her it its we us our they them their
                this that these those not no who whom which what have has had do does did
                will shall would should may might can could so but if then than there here
                up out into upon over under all any some one o)

  @type t :: map()

  @doc """
  The card for a tool's details, or nil when the tool names no passage
  (another tool, an error, a word with no entry or no examples).
  """
  @spec from_tool(String.t(), term()) :: t() | nil
  def from_tool("lookup_verse", %{verses: [_ | _] = verses} = result) do
    one_chapter? = match?([_], Enum.uniq_by(verses, & &1.chapter))

    ref = fn v ->
      if one_chapter?, do: "#{v.verse}", else: "#{v.chapter}:#{v.verse}"
    end

    card(result, "lookup_verse", result.label || result.reference, verses, ref, fn _ -> true end)
  end

  def from_tool(
        "word_study",
        %{entry: %{"strongs" => strongs} = entry, examples: [_ | _] = ex} = result
      ) do
    title = Enum.join(Enum.reject([strongs, entry["transliteration"]], &blank?/1), " · ")
    display = &Reference.display(&1.reference)
    card(result, "word_study", title, ex, display, &same_strongs?(&1, strongs))
  end

  def from_tool(_name, _details), do: nil

  @doc "The card's English, verse by verse, for copying: `2 See, I have called…`."
  @spec text(t()) :: String.t()
  def text(%{"title" => title, "verses" => verses} = card) do
    version = if card["version"] in [nil, ""], do: nil, else: card["version"]

    body =
      Enum.map_join(verses, " ", fn v ->
        own = if v["version"] && v["version"] != version, do: " (#{v["version"]})", else: ""
        v["ref"] <> " " <> Enum.map_join(v["tokens"], " ", &hd/1) <> own
      end)

    "#{body} (#{title}#{if version, do: ", " <> version, else: ""})"
  end

  defp card(result, from, title, verses, ref, highlight?) do
    {shown, rest} = Enum.split(verses, @max_verses)
    translation = Map.get(result, :translation)

    {rows, words} =
      Enum.map_reduce(shown, %{}, fn v, words ->
        index = gloss_index(v.words, highlight?)

        tokens =
          for token <- String.split(v.english, " ", trim: true),
              do: [token, Map.get(index, bare(token))]

        found = for [_, s] <- tokens, s, into: %{}, do: {s, word(v.words, s)}

        row = %{
          "ref" => ref.(v),
          "tokens" => tokens,
          "url" => verse_url(v, translation),
          "version" => if(fallback?(v), do: "BSB")
        }

        {Map.reject(row, fn {_k, value} -> value == nil end), Map.merge(found, words)}
      end)

    %{
      "from" => from,
      "title" => title,
      "version" => version(shown, translation),
      "version_url" => version_url(shown, rows, translation),
      "verses" => rows,
      "words" => words,
      "more" => length(rest)
    }
  end

  # The card's translation: the result's when any verse shown is its text,
  # the BSB when every quoted verse is the BSB standing in, else "".
  defp version(_shown, nil), do: ""

  defp version(shown, translation) do
    case Enum.filter(shown, & &1.translated) do
      [] -> ""
      quoted -> if Enum.all?(quoted, &fallback?/1), do: "BSB", else: translation.abbreviation
    end
  end

  # The NET's link: the first verse quoted in the NET's page.
  defp version_url(shown, rows, %{key: "net", url: url}) do
    if Enum.any?(shown, &(&1.translated and not fallback?(&1))),
      do: Enum.find_value(rows, url, &(&1["version"] == nil && &1["url"]))
  end

  defp version_url(_shown, _rows, _translation), do: nil

  # A verse whose English is the BSB standing in for a translation that
  # lacks its book (`Bezalel.Study.Format.verse_view/1`'s `fallback`).
  defp fallback?(verse), do: Map.get(verse, :fallback) == true

  # The verse's page in the translation it's quoted in (`Bezalel.Study.Citations`;
  # the BSB's for a verse the BSB stands in for); nil for a verse shown only
  # as STEPBible's gloss.
  defp verse_url(%{translated: true, reference: "" <> reference} = verse, %{key: key}) do
    key = if Map.get(verse, :fallback) == true, do: "bsb", else: key
    if key in Translations.keys(), do: Citations.scripture(reference, key).url
  end

  defp verse_url(_verse, _translation), do: nil

  # Content word of a gloss → the Strong's number of the first original
  # word glossed with it.
  defp gloss_index(words, highlight?) do
    words
    |> Enum.filter(&(not blank?(&1.strongs) and highlight?.(&1.strongs)))
    |> Enum.flat_map(fn w -> for g <- gloss_words(w.gloss), do: {g, w.strongs} end)
    |> Enum.reverse()
    |> Map.new()
  end

  defp gloss_words(gloss) do
    gloss
    |> String.split([" ", "/", "-"], trim: true)
    |> Enum.reject(&(String.starts_with?(&1, "[") or String.starts_with?(&1, "<")))
    |> Enum.map(&bare/1)
    |> Enum.reject(&(&1 == "" or &1 in @stopwords))
  end

  defp bare(token),
    do: Regex.replace(Patterns.get(:word_edges), String.downcase(token), "")

  defp word(words, strongs) do
    w = Enum.find(words, &(&1.strongs == strongs))

    %{
      "strongs" => strongs,
      "word" => String.replace(w.word, ["/", "\\"], ""),
      "translit" => String.replace(w.transliteration, "/", ""),
      "gloss" => String.replace(w.gloss, "/ ", " "),
      "morph" => w.morph
    }
  end

  # "H7307G" is a sense of "H7307".
  defp same_strongs?(word_strongs, strongs) do
    String.starts_with?(word_strongs, strongs) and
      not match?(<<d, _::binary>> when d in ?0..?9, binary_part_after(word_strongs, strongs))
  end

  defp binary_part_after(text, prefix),
    do: binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix))

  defp blank?(value), do: value in [nil, ""]
end
