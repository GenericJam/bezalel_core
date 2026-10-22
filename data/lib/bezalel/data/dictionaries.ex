defmodule Bezalel.Data.Dictionaries do
  @moduledoc """
  The UBS dictionaries (ubsicap/ubs-open-license, CC BY-SA 4.0) → the
  `dictionaries` pack's rows: the UBS Dictionary of Biblical Hebrew (from
  the Semantic Dictionary of Biblical Hebrew) and the UBS Dictionary of the
  Greek New Testament (from Louw & Nida), English, from their JSON.

  Per entry: the lemma and its Strong's codes as given (`H0003 A0004`), and
  each code normalised to the core lexicon's key (`dictionary_strongs`:
  `A0004` → `H0004`, as Strong's numbers Aramaic words in the Hebrew range;
  a letter suffix, `H0032b`, → `H0032`). Per meaning: its id, part of
  speech, Louw–Nida number (Greek), lexical domain and subdomain codes,
  short definition, glosses, comments and how many references the source
  lists (the references themselves aren't imported: `word_study` doesn't
  show them).

  Domain names come from the dictionaries' lexical-domain files. A domain
  an entry names differently from that file (an upstream slip: 14 Hebrew
  meanings name the top-level codes 001–003 with the contextual domains'
  labels) is left out and listed in the report, as is a domain source
  (`Stage` of `Vegetation`) named differently.

  The text's markup is rendered by rule (`clean/3`); anything else in
  `{X:…}`, `<…>` or `|` form stops the build. A sense the source marks
  `AIGenerated` is not imported.
  """

  alias Bezalel.Data.{Books, Scrolls}

  @by_sa "CC BY-SA 4.0"
  @by_sa_url "https://creativecommons.org/licenses/by-sa/4.0/"
  @licence_line "Creative Commons Attribution-ShareAlike 4.0 International License"

  @dictionaries [
    %{
      key: "ubs_hebrew",
      title: "UBS Dictionary of Biblical Hebrew",
      edition: "v0.9.4, English",
      language: "hebrew",
      prefixes: ~w(H A),
      entries: "dictionaries/hebrew/JSON/UBSHebrewDic-v0.9.4-en.JSON",
      domains: "dictionaries/hebrew/JSON/UBSHebrewDicLexicalDomains-v0.9.4-en.JSON",
      readme: "dictionaries/hebrew/README.md",
      attribution:
        "UBS Dictionary of Biblical Hebrew © United Bible Societies, 2023. " <>
          "Adapted from Semantic Dictionary of Biblical Hebrew © 2000-2023 United Bible Societies."
    },
    %{
      key: "ubs_greek",
      title: "UBS Dictionary of the Greek New Testament",
      edition: "v1.1, English",
      language: "greek",
      prefixes: ~w(G),
      entries: "dictionaries/greek/JSON/UBSGreekNTDic-v1.1-en.JSON",
      domains: "dictionaries/greek/JSON/UBSGreekNTDicLexicalDomains-v1.1-en.JSON",
      readme: "dictionaries/greek/README.md",
      # The README's words; its soft hyphen ("Testa­ment") left out.
      attribution:
        "UBS Dictionary of New Testament Greek, © United Bible Societies, 2023. " <>
          "Adapted from Semantic Dictionary of Biblical Greek: © United Bible Societies " <>
          "2018-2023, which is adapted from Greek-English Lexicon of the New Testament: " <>
          "Based on Semantic Domains, Eds. J P Louw, Eugene Albert Nida © United Bible " <>
          "Societies 1988, 1989."
    }
  ]

  # The code and data that decide the pack's rows, relative to data/.
  @build_inputs ~w(
    lib/bezalel/data/dictionaries.ex lib/bezalel/data/dictionaries_pack.ex
    lib/bezalel/data/pack.ex lib/bezalel/data/books.ex lib/bezalel/data/scrolls.ex lib/bezalel/data/download.ex
    lib/mix/tasks/bezalel.data.dictionaries.ex
  )

  @type dictionary :: %{
          key: String.t(),
          title: String.t(),
          edition: String.t(),
          language: String.t(),
          prefixes: [String.t()],
          entries: String.t(),
          domains: String.t(),
          readme: String.t(),
          attribution: String.t()
        }

  @typedoc """
  `{book, chapter, verse}` in the source's (Hebrew) numbering → the packs'
  English `{chapter, verse}`, or nil (`Bezalel.Data.Scrolls.english_numbering/1`).
  """
  @type english :: ({String.t(), pos_integer(), non_neg_integer()} ->
                      {pos_integer(), non_neg_integer()} | nil)

  @doc "The two dictionaries, Hebrew first."
  @spec dictionaries() :: [dictionary()]
  def dictionaries, do: @dictionaries

  @doc "The files read, as paths in the repository."
  @spec files() :: [String.t()]
  def files, do: Enum.flat_map(@dictionaries, &[&1.readme, &1.entries, &1.domains])

  @doc "The licence label and URL every dictionary's rows carry."
  @spec licence() :: {String.t(), String.t()}
  def licence, do: {@by_sa, @by_sa_url}

  @doc """
  One checksum of the files that decide the pack's rows (`@build_inputs`,
  relative to `data/`), recorded in `pack_meta.build_sha256`.
  """
  @spec build_digest() :: String.t()
  def build_digest do
    root = Path.expand("../../..", __DIR__)

    @build_inputs
    |> Enum.map(fn path ->
      [path, ?\t, sha256(File.read!(Path.join(root, path))), ?\n]
    end)
    |> sha256()
  end

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  @doc """
  `:ok` if `readme` grants CC BY-SA 4.0 and carries the attribution the
  pack records for `dictionary`; else `{:error, reason}`.
  """
  @spec check_licence(binary(), dictionary()) :: :ok | {:error, String.t()}
  def check_licence(readme, dictionary) do
    flat = readme |> String.replace("\u00AD", "") |> String.replace(regex(~S"\s+"), " ")

    cond do
      not String.contains?(flat, @licence_line) ->
        {:error, "#{dictionary.readme} no longer grants #{@by_sa}"}

      not String.contains?(flat, "(" <> dictionary.attribution <> ")") ->
        {:error, "#{dictionary.readme} no longer gives the attribution recorded"}

      true ->
        :ok
    end
  end

  @doc """
  The core lexicon's key for a Strong's code as the dictionaries give it,
  `prefix` the dictionary's letter (`"H"`, `"G"`): `A0004` (Aramaic) →
  `H0004`, `H0032b` → `H0032`, a bare `2062` → `H2062`, `G0026` unchanged.
  nil for an empty code or a compound name's (`H0410+H1285`, El-Berith):
  neither number alone is that word. Raises on any other form.
  """
  @spec normalize_strongs(String.t(), String.t()) :: String.t() | nil
  def normalize_strongs("", _prefix), do: nil

  def normalize_strongs(code, prefix) do
    cond do
      String.contains?(code, "+") ->
        nil

      match = Regex.run(regex(~S"^([HAG]?)([0-9]{4})[a-z]?$"), code) ->
        case match do
          [_, "", number] -> prefix <> number
          [_, "A", number] -> "H" <> number
          [_, given, number] -> given <> number
        end

      true ->
        raise ArgumentError, "unknown Strong's code #{inspect(code)}"
    end
  end

  # How a code is given, for the report.
  defp code_form(code) do
    cond do
      String.contains?(code, "+") -> "compound"
      Regex.match?(regex(~S"^[0-9]"), code) -> "no prefix"
      Regex.match?(regex(~S"[a-z]$"), code) -> String.first(code) <> " with a letter"
      true -> String.first(code)
    end
  end

  defp unreachable(lemma, []), do: lemma
  defp unreachable(lemma, codes), do: "#{lemma} (#{Enum.join(codes, " ")})"

  @doc """
  `Bezalel.Data.Scrolls.english_numbering/1` over the core pack's
  references, the NT's alternative numbers (`Php.1.16[1.17]`,
  `2Co.1.7{1.6}`) dropped first: the packs number those verses by the
  reference before the bracket, the numbering the UBS text's NT references
  share (`Php.1.17` is Php 1:17).
  """
  @spec english_numbering([String.t()]) :: english()
  def english_numbering(references) do
    alternative = regex(~S"[\[{][0-9]+\.[0-9]+[\]}]$")
    references |> Enum.map(&Regex.replace(alternative, &1, "")) |> Scrolls.english_numbering()
  end

  @doc "The domain file's codes → `%{name, level}` (English labels)."
  @spec domains(binary()) :: %{String.t() => %{name: String.t(), level: pos_integer()}}
  def domains(json) do
    json
    |> Jason.decode!()
    |> Map.new(fn domain ->
      [%{"Label" => label}] =
        Enum.filter(domain["SemanticDomainLocalizations"], &(&1["LanguageCode"] == "en"))

      {domain["Code"], %{name: label, level: domain["Level"]}}
    end)
  end

  @doc """
  The rows of one dictionary: `json` its entries file, `domains` from
  `domains/1`, `english` mapping the source's verse numbers to the packs'.
  Returns `%{entries, strongs, meanings, meaning_domains, domains, stats}`;
  `stats` counts what the report lists.
  """
  @spec load(binary(), map(), dictionary(), english()) :: map()
  def load(json, domains, dictionary, english) do
    acc = %{
      entries: [],
      strongs: [],
      meanings: [],
      meaning_domains: [],
      stats: %{
        no_strongs: [],
        references: 0,
        ai_generated: 0,
        no_sense: 0,
        dropped_domains: [],
        dropped_sources: [],
        markup: %{},
        prefixes: %{}
      }
    }

    acc =
      json |> Jason.decode!() |> Enum.reduce(acc, &entry(&1, &2, domains, dictionary, english))

    meaning_ids = Enum.map(acc.meanings, & &1.meaning_id)

    if length(Enum.uniq(meaning_ids)) != length(meaning_ids),
      do: raise("#{dictionary.entries}: a meaning id is repeated")

    domain_rows =
      domains
      |> Enum.sort()
      |> Enum.map(fn {code, d} ->
        %{dictionary: dictionary.key, code: code, name: d.name, level: d.level}
      end)

    %{
      entries: Enum.reverse(acc.entries),
      strongs: acc.strongs |> Enum.reverse() |> Enum.sort_by(&{&1.strongs, &1.entry_id}),
      meanings: Enum.reverse(acc.meanings),
      meaning_domains: Enum.reverse(acc.meaning_domains),
      domains: domain_rows,
      stats: %{
        acc.stats
        | no_strongs: Enum.reverse(acc.stats.no_strongs),
          dropped_domains: Enum.reverse(acc.stats.dropped_domains),
          dropped_sources: Enum.reverse(acc.stats.dropped_sources)
      }
    }
  end

  defp entry(entry, acc, domains, dictionary, english) do
    id = entry["MainId"]
    given = Enum.reject(entry["StrongCodes"] || [], &(&1 == ""))
    prefix = String.first(hd(dictionary.prefixes))

    keyed =
      given
      |> Enum.map(&{normalize_strongs(&1, prefix), &1})
      |> Enum.reject(&match?({nil, _}, &1))

    for {key, code} <- keyed, not String.starts_with?(key, prefix) do
      raise "#{dictionary.entries}: #{id} has #{code}, not a #{dictionary.language} code"
    end

    strongs =
      keyed
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {normalized, codes} ->
        %{
          strongs: normalized,
          dictionary: dictionary.key,
          entry_id: id,
          given: Enum.join(codes, " ")
        }
      end)

    stats =
      Enum.reduce(given, acc.stats, fn code, stats ->
        update_in(stats.prefixes, &Map.update(&1, code_form(code), 1, fn n -> n + 1 end))
      end)

    stats =
      if keyed == [],
        do: %{stats | no_strongs: [unreachable(entry["Lemma"], given) | stats.no_strongs]},
        else: stats

    row = %{
      dictionary: dictionary.key,
      entry_id: id,
      lemma: entry["Lemma"],
      strong_codes: Enum.join(given, " ")
    }

    meanings =
      for base <- entry["BaseForms"] || [],
          meaning <- base["LEXMeanings"] || [],
          do: {Enum.join(base["PartsOfSpeech"] || [], ", "), meaning}

    acc = %{
      acc
      | entries: [row | acc.entries],
        strongs: Enum.reverse(strongs, acc.strongs),
        stats: stats
    }

    meanings
    |> Enum.with_index(1)
    |> Enum.reduce(acc, fn {{pos, meaning}, position}, acc ->
      meaning(meaning, {id, position, pos}, acc, domains, dictionary, english)
    end)
  end

  defp meaning(meaning, {entry_id, position, pos}, acc, domains, dictionary, english) do
    id = meaning["LEXID"]
    senses = Enum.filter(meaning["LEXSenses"] || [], &(&1["LanguageCode"] == "en"))
    {ai, human} = Enum.split_with(senses, &(&1["AIGenerated"] == true))
    stats = %{acc.stats | ai_generated: acc.stats.ai_generated + length(ai)}

    {sense, stats} =
      case human do
        [sense | _] -> {sense, stats}
        [] -> {%{}, %{stats | no_sense: stats.no_sense + 1}}
      end

    {definition, stats} = clean_field(sense["DefinitionShort"], :definition, stats, english)
    {comments, stats} = clean_field(sense["Comments"], :comments, stats, english)

    {glosses, stats} =
      Enum.map_reduce(sense["Glosses"] || [], stats, &clean_field(&1, :gloss, &2, english))

    references = length(meaning["LEXReferences"] || [])

    row = %{
      dictionary: dictionary.key,
      entry_id: entry_id,
      meaning_id: id,
      position: position,
      part_of_speech: blank_nil(pos),
      louw_nida: blank_nil(meaning["LEXEntryCode"]),
      definition: definition,
      glosses: Jason.encode!(Enum.reject(glosses, &is_nil/1)),
      comments: comments,
      reference_count: references
    }

    {domain_rows, stats} =
      [{"domain", meaning["LEXDomains"]}, {"subdomain", meaning["LEXSubDomains"]}]
      |> Enum.flat_map(fn {kind, list} -> Enum.map(list || [], &{kind, &1}) end)
      |> Enum.reduce({[], stats}, &domain(&1, &2, id, domains, dictionary))

    %{
      acc
      | meanings: [row | acc.meanings],
        meaning_domains: Enum.reverse(domain_rows, acc.meaning_domains),
        stats: %{stats | references: stats.references + references}
    }
  end

  defp domain({kind, domain}, {rows, stats}, meaning_id, domains, dictionary) do
    code = domain["DomainCode"]
    given = domain["Domain"]

    case domains[code] do
      nil ->
        raise "#{dictionary.entries}: #{meaning_id} names domain #{code}, which " <>
                "#{dictionary.domains} lacks"

      %{name: name} when name != given ->
        dropped = {meaning_id, code, given, name}
        {rows, %{stats | dropped_domains: [dropped | stats.dropped_domains]}}

      _named ->
        {source, stats} = domain_source(domain, meaning_id, domains, stats)
        position = Enum.count(rows, &(&1.kind == kind)) + 1

        row = %{
          dictionary: dictionary.key,
          meaning_id: meaning_id,
          kind: kind,
          position: position,
          code: code,
          source_code: source
        }

        {rows ++ [row], stats}
    end
  end

  defp domain_source(%{"DomainSourceCode" => code} = domain, meaning_id, domains, stats)
       when code not in [nil, ""] do
    given = domain["DomainSource"]

    case domains[code] do
      %{name: ^given} ->
        {code, stats}

      other ->
        dropped = {meaning_id, code, given, other && other.name}
        {nil, %{stats | dropped_sources: [dropped | stats.dropped_sources]}}
    end
  end

  defp domain_source(_domain, _meaning_id, _domains, stats), do: {nil, stats}

  defp clean_field(text, _kind, stats, _english) when text in [nil, ""], do: {nil, stats}

  defp clean_field(text, kind, stats, english) do
    {clean, counts} = clean(text, kind, english)

    {blank_nil(clean),
     %{stats | markup: Map.merge(stats.markup, counts, fn _k, a, b -> a + b end)}}
  end

  defp blank_nil(nil), do: nil
  defp blank_nil(""), do: nil
  defp blank_nil(text), do: text

  @doc """
  The source's markup rendered, with a count of each rule applied:

    * `{L:text<SDBH:…>}`, a link to another entry: its text;
    * `{D:25.43}`, a Louw–Nida entry: `LN 25.43`;
    * `{S:BBBCCCVVV…}`, a Scripture reference: the verse in STEP form in
      the packs' English numbering (`english`); one the core pack lacks
      stops the build;
    * `{A:NIV}`, an abbreviation (a version or a reference work): the
      abbreviation;
    * `{N:001}`, a footnote marker: dropped (the notes aren't imported);
    * `|i…|i*`, italics (a species name): the text;
    * in comments, `|` between paragraphs: a space.

  Whitespace is collapsed. Any other `{X:`, `<`, `>` or `|` raises.
  """
  @spec clean(String.t(), :definition | :comments | :gloss, english()) ::
          {String.t(), %{String.t() => pos_integer()}}
  def clean(text, kind, english) do
    rules = [
      {"link", ~S"\{L:([^<{}]*)<[^>]*>\}", fn _, t -> t end},
      {"louw_nida", ~S"\{D:([0-9]+\.[0-9]+[a-z]?)\}", fn _, n -> "LN " <> n end},
      # One comment (σαργάνη) closes a Louw–Nida number with its parenthesis.
      {"louw_nida_unclosed", ~S"\{D:([0-9]+\.[0-9]+[a-z]?)\)", fn _, n -> "LN " <> n <> ")" end},
      {"scripture", ~S"\{S:([0-9][0-9 -]*)\}", fn _, refs -> references(refs, english) end},
      {"abbreviation", ~S"\{A:([A-Z][A-Za-z-]*)\}", fn _, a -> a end},
      {"footnote", ~S"\{N:[0-9]+\}", fn _ -> "" end},
      {"italics", ~S"\|i(.*?)\|i\*", fn _, t -> t end}
    ]

    rules =
      if kind == :comments, do: rules ++ [{"paragraph", ~S"\|", fn _ -> " " end}], else: rules

    {text, counts} =
      Enum.reduce(rules, {text, %{}}, fn {name, source, render}, {text, counts} ->
        pattern = regex(source)

        case length(Regex.scan(pattern, text)) do
          0 -> {text, counts}
          n -> {Regex.replace(pattern, text, render), Map.put(counts, name, n)}
        end
      end)

    if Regex.match?(regex(~S"\{[A-Z]+:|<[A-Z][A-Z-]*:|\|"), text),
      do: raise(ArgumentError, "unknown markup in #{inspect(text)}")

    {text |> String.replace(regex(~S"\s+"), " ") |> String.trim(), counts}
  end

  # Space-separated word references, or a range (`A-B`): their verses, each once.
  defp references(refs, english) do
    refs
    |> String.split(" ", trim: true)
    |> Enum.map(fn token ->
      token
      |> String.split("-")
      |> Enum.map_join("–", &reference(binary_part(&1, 0, 9), english))
    end)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  # Verse 000 is the whole chapter (`Lev.11`), numbered as its first verse is.
  defp reference(digits, english) do
    <<book::binary-3, chapter::binary-3, verse::binary-3>> = digits
    {code, _name, _chapters} = Enum.at(Books.all(), String.to_integer(book) - 1)
    {chapter, verse} = {String.to_integer(chapter), String.to_integer(verse)}

    case {verse, english.({code, chapter, max(verse, 1)})} do
      {0, {c, _v}} ->
        "#{code}.#{c}"

      {_, {c, v}} ->
        "#{code}.#{c}.#{v}"

      {_, nil} ->
        raise ArgumentError, "{S:#{digits}…}: the core pack has no #{code} #{chapter}:#{verse}"
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
