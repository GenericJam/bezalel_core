defmodule Bezalel.Data.Witnesses do
  @moduledoc """
  The `witnesses` pack's rows, from four pinned sources (`pins.json` →
  `sp`, `sblgnt`, `hottp`), each in tables of its own with its own licence:

    * **The Samaritan Pentateuch** (DT-UCPH/sp, Text-Fabric 7.2.4, CC BY-NC
      4.0): per verse, the consonantal text as the dataset spells its words
      (`g_cons_utf8`, each followed by its `trailer`), filed under the packs'
      English reference and keeping the dataset's own (Hebrew-style)
      numbering. The dataset groups the additions after Gen 30:36 under
      verse 36, which the row says.
    * **The SBL Greek New Testament** (Faithlife/SBLGNT, CC BY 4.0): one row
      per verse of `data/sblgnt/text`, as the file gives it (the ⸀ ⸂ ⸃ marks
      that point to the apparatus kept).
    * **The SBLGNT apparatus** (same repository and licence): every note of
      `data/sblgntapp/xml`, raw, and parsed into its variation unit: the
      SBLGNT's reading with the editions supporting it, then each variant
      with its editions. A note that doesn't fit the apparatus's grammar is
      kept raw and marked unparsed, never guessed at.
    * **The UBS Hebrew Old Testament Text Project** (ubsicap/ubs-open-license,
      CC BY-SA 4.0), English only: each entry's remark and suggestion, its
      verses (its 14-digit `BBBCCCVVVWWWWW` references, Hebrew numbering,
      filed under the packs' English reference), each alternative reading
      (Hebrew, the committee's rating, factors, the base translations'
      renderings, literal English), and the glossaries of the ratings and
      factors from the report's introduction.

  The Hebrew-numbered sources are mapped to English numbering with the base
  core pack's `verses.reference` (`Bezalel.Data.Scrolls.english_numbering/1`).
  The New Testament keeps the SBLGNT's numbering, which is the core pack's
  `verses` numbering (every SBLGNT verse is a core verse; the build checks).
  """

  alias Bezalel.Data.{Books, Scrolls, TextFabric, Xml}

  @sp_features ~w(otype oslots book chapter verse g_cons_utf8 trailer)
  @sp_books %{
    "Genesis" => "Gen",
    "Exodus" => "Exo",
    "Leviticus" => "Lev",
    "Numbers" => "Num",
    "Deuteronomy" => "Deu"
  }
  # The dataset's verse division where it departs from the MT's: Gen 30:36
  # as its README says; Exod 26:35 and Deut 34:1 as its text shows (it has
  # no Exod 30:1–10 and no Deut 34:2–3; the report lists every core Torah
  # verse it lacks).
  @sp_notes %{
    "Gen.30.36" =>
      "The dataset groups under verse 36 the Samaritan Pentateuch's additions after it " <>
        "(numbered 36a, 36b and 36c in other editions).",
    "Exo.26.35" =>
      "The Samaritan Pentateuch has the incense altar (the MT's Exodus 30:1–10) after this " <>
        "verse; the dataset numbers it as part of 26:35 and has no 30:1–10.",
    "Deu.34.1" =>
      "The dataset has no 34:2–3: its 34:1 ends with its own description of the land " <>
        "(from the river of Egypt to the Euphrates and the western sea) where the MT's " <>
        "34:1–3 lists the regions."
  }

  # The SBLGNT's file names, in canonical order, and their STEP codes.
  @sblgnt_books [
    {"Matt", "Mat"},
    {"Mark", "Mrk"},
    {"Luke", "Luk"},
    {"John", "Jhn"},
    {"Acts", "Act"},
    {"Rom", "Rom"},
    {"1Cor", "1Co"},
    {"2Cor", "2Co"},
    {"Gal", "Gal"},
    {"Eph", "Eph"},
    {"Phil", "Php"},
    {"Col", "Col"},
    {"1Thess", "1Th"},
    {"2Thess", "2Th"},
    {"1Tim", "1Ti"},
    {"2Tim", "2Ti"},
    {"Titus", "Tit"},
    {"Phlm", "Phm"},
    {"Heb", "Heb"},
    {"Jas", "Jas"},
    {"1Pet", "1Pe"},
    {"2Pet", "2Pe"},
    {"1John", "1Jn"},
    {"2John", "2Jn"},
    {"3John", "3Jn"},
    {"Jude", "Jud"},
    {"Rev", "Rev"}
  ]

  # The apparatus's sigla (SBLGNT introduction, "Abbreviations Used in the
  # Notes", and Logos's 2013 update to NA28). `em` (emendation) precedes
  # the siglum of the edition that adopts or proposes one.
  @sigla ~w(WH ⟦WH⟧ WHmarg WHapp Treg Tregmarg NA28 NA27 NIV RP TR Greeven Holmes em)

  @hottp_entry ~w(References Remark Remark-FR Suggestion SuggestionFR Alternatives)
  @hottp_alternative ~w(Source Rating Versions Factors Literal LiteralFR)
  @hottp_french ~w(Remark-FR SuggestionFR LiteralFR)
  # Backslashes the report's English text has that are not markup (a typo
  # for "(come)" in an entry's remark), kept as given.
  @hottp_literal_backslashes ["(\\come)"]

  # The code and data that decide the pack's rows, relative to data/.
  @build_inputs ~w(
    lib/bezalel/data/witnesses.ex lib/bezalel/data/witnesses_pack.ex
    lib/bezalel/data/xml.ex lib/bezalel/data/text_fabric.ex lib/bezalel/data/pack.ex
    lib/bezalel/data/scrolls.ex lib/bezalel/data/books.ex
    lib/mix/tasks/bezalel.data.witnesses.ex
  )

  @doc "The SP feature files read, as file names."
  @spec sp_files() :: [String.t()]
  def sp_files, do: Enum.map(@sp_features, &"#{&1}.tf")

  @doc "The apparatus's sigla."
  @spec sigla() :: [String.t()]
  def sigla, do: @sigla

  @doc "sha256 of `bytes`, lower-case hex."
  @spec sha256(iodata()) :: String.t()
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc "One checksum of a set of files: sha256 over `name<TAB>sha256<LF>`, names sorted."
  @spec digest(%{String.t() => String.t()} | [{String.t(), String.t()}]) :: String.t()
  def digest(sha256s) do
    sha256s |> Enum.sort() |> Enum.map(fn {name, sha} -> [name, ?\t, sha, ?\n] end) |> sha256()
  end

  @doc """
  One checksum of the files that decide the pack's rows (`@build_inputs`),
  recorded in `pack_meta.build_sha256` so a publish can tell a pack built by
  other code.
  """
  @spec build_digest() :: String.t()
  def build_digest do
    root = Path.expand("../../..", __DIR__)
    @build_inputs |> Map.new(&{&1, sha256(File.read!(Path.join(root, &1)))}) |> digest()
  end

  # --- The Samaritan Pentateuch -----------------------------------------------

  @doc """
  The Samaritan Pentateuch's verse rows from the Text-Fabric files (`read`:
  file name → bytes). `english` maps a Hebrew-numbered `{book, chapter,
  verse}` to the core pack's English `{chapter, verse}` (nil: no such
  verse). Returns `%{verses: rows, unmapped: source references}`; raises on
  a word outside every verse, a verse without words, or one verse number
  twice. Two verses can share an English reference: the core pack's
  English Num 26:1 is Hebrew 25:19 and 26:1, and each keeps its own row.
  """
  @spec samaritan((String.t() -> binary()), (tuple() -> {integer(), integer()} | nil)) :: map()
  def samaritan(read, english) do
    types = TextFabric.types(read.("otype.tf"), ~w(sign book chapter verse word))
    ranges = Map.take(types, ~w(book chapter verse word))
    {first, _} = ranges |> Map.values() |> Enum.min()
    {_, last} = ranges |> Map.values() |> Enum.max_by(&elem(&1, 1))
    slots = TextFabric.slots(read.("oslots.tf"), first, last)

    feature = fn name, type ->
      {low, high} = types[type]
      TextFabric.feature(name, read.(name), low, high)
    end

    nodes = fn type, values ->
      {low, high} = types[type]
      for node <- low..high//1, do: {node, Map.fetch!(slots, node), Map.get(values, node)}
    end

    books = nodes.("book", feature.("book.tf", "book"))
    chapters = nodes.("chapter", feature.("chapter.tf", "chapter"))
    verses = nodes.("verse", feature.("verse.tf", "verse"))
    cons = feature.("g_cons_utf8.tf", "word")
    trailers = feature.("trailer.tf", "word")

    words =
      "word"
      |> nodes.(cons)
      |> Enum.map(fn {node, range, letters} ->
        {range, (letters || "") <> Map.get(trailers, node, "")}
      end)
      |> Enum.sort_by(fn {range, _} -> range.first end)

    {rows, rest} = Enum.map_reduce(verses, words, &sp_verse(&1, &2, books, chapters, english))

    if rest != [] do
      raise ArgumentError, "sp: #{length(rest)} words after the last verse"
    end

    check_unique!(rows, :source_reference, "sp")
    %{verses: rows, unmapped: for(%{mt_verse: 0} = row <- rows, do: row.source_reference)}
  end

  defp sp_verse({node, range, number}, words, books, chapters, english) do
    {mine, rest} = Enum.split_while(words, fn {slots, _} -> slots.last <= range.last end)

    if mine == [] or Enum.any?(mine, fn {slots, _} -> slots.first < range.first end) do
      raise ArgumentError, "sp: verse node #{node} has no words of its own"
    end

    book = @sp_books |> Map.fetch!(containing!(books, range, node))
    chapter = chapters |> containing!(range, node) |> String.to_integer()
    verse = String.to_integer(number)
    source = "#{book}.#{chapter}.#{verse}"

    {reference, mapped} =
      case english.({book, chapter, verse}) do
        {c, v} -> {{c, v}, 1}
        nil -> {{chapter, verse}, 0}
      end

    {c, v} = reference

    row = %{
      reference: "#{book}.#{c}.#{v}",
      book: book,
      chapter: c,
      verse: v,
      source_reference: source,
      mt_verse: mapped,
      text: mine |> Enum.map_join(&elem(&1, 1)) |> String.trim(),
      words: length(mine),
      note: @sp_notes[source]
    }

    {row, rest}
  end

  defp containing!(nodes, range, node) do
    case Enum.find(nodes, fn {_, slots, _} ->
           slots.first <= range.first and range.last <= slots.last
         end) do
      {_, _, value} when is_binary(value) -> value
      _ -> raise ArgumentError, "sp: verse node #{node} is in no book or chapter"
    end
  end

  defp check_unique!(rows, key, name) do
    case rows |> Enum.frequencies_by(&Map.fetch!(&1, key)) |> Enum.filter(&(elem(&1, 1) > 1)) do
      [] -> :ok
      twice -> raise ArgumentError, "#{name}: references filed twice: #{inspect(twice)}"
    end
  end

  # --- The SBLGNT text --------------------------------------------------------

  @doc "The SBLGNT's file stems and STEP book codes, in canonical order."
  @spec sblgnt_books() :: [{String.t(), String.t()}]
  def sblgnt_books, do: @sblgnt_books

  @doc """
  The SBLGNT's verse rows from its text files (`stem` → bytes): each file is
  a title line, then `<stem> <chapter>:<verse><TAB><text>` lines. Raises on
  any other line.
  """
  @spec sblgnt_text(%{String.t() => binary()}) :: [map()]
  def sblgnt_text(files) do
    pattern = regex(~S"^(\S+) ([0-9]+):([0-9]+)\t(.*)$")

    rows =
      Enum.flat_map(@sblgnt_books, fn {stem, book} ->
        [_title | lines] = files |> Map.fetch!(stem) |> String.split("\n")

        lines
        |> Enum.with_index(2)
        |> Enum.reject(fn {line, _} -> line == "" end)
        |> Enum.map(&sblgnt_line(&1, stem, book, pattern))
      end)

    check_unique!(rows, :reference, "sblgnt")
    rows
  end

  defp sblgnt_line({line, number}, stem, book, pattern) do
    case Regex.run(pattern, line) do
      [_, ^stem, chapter, verse, text] ->
        %{
          reference: "#{book}.#{chapter}.#{verse}",
          book: book,
          chapter: String.to_integer(chapter),
          verse: String.to_integer(verse),
          text: String.trim(text),
          file: stem,
          line: number
        }

      _ ->
        raise ArgumentError, "sblgnt #{stem}.txt line #{number}: #{inspect(line)}"
    end
  end

  # --- The SBLGNT apparatus ---------------------------------------------------

  @doc """
  The apparatus's variation units from its XML files (`stem` → bytes): a
  `<verse>` (`John 1:18`) followed by its `<note>`s, the first starting with
  the verse number (`18`, `1:15` at a chapter's start, `22–23` for a unit
  spanning verses), the others with `•`. Each unit is parsed into
  `lemma` (the SBLGNT's reading) with `lemma_sigla` and `variants`
  (`%{text, sigla}`; ";" separates them), or kept raw with `parsed: false`
  and the reason in `refused`.
  """
  @spec apparatus(%{String.t() => binary()}) :: %{units: [map()], refused: [map()]}
  def apparatus(files) do
    names = Map.new(Books.all(), fn {code, name, _} -> {name, code} end)

    units =
      Enum.flat_map(@sblgnt_books, fn {stem, book} ->
        {"book", _, children, _} = root = Xml.parse!("#{stem}.xml", Map.fetch!(files, stem))

        unless Enum.all?(children, &(is_tuple(&1) or String.trim(&1) == "")) do
          raise ArgumentError, "sblgnt apparatus #{stem}.xml: text outside an element"
        end

        root
        |> Xml.elements()
        |> Enum.reject(&match?({"book-name", _, _, _}, &1))
        |> Enum.chunk_while(nil, &chunk_verse(&1, &2, stem), &last_verse/1)
        |> Enum.flat_map(&verse_units(&1, book, names, stem))
      end)

    %{
      units: units,
      refused: for(%{parsed: false} = unit <- units, do: unit)
    }
  end

  # The file's last verse, its notes (gathered last first) back in order.
  defp last_verse(nil), do: {:cont, nil}
  defp last_verse({verse, notes}), do: {:cont, {verse, Enum.reverse(notes)}, nil}

  # Groups each <verse> with the <note>s after it.
  defp chunk_verse({"verse", _, _, _} = verse, nil, _stem), do: {:cont, {verse, []}}

  defp chunk_verse({"verse", _, _, _} = verse, {previous, notes}, _stem),
    do: {:cont, {previous, Enum.reverse(notes)}, {verse, []}}

  defp chunk_verse({"note", _, _, _} = note, {verse, notes}, _stem),
    do: {:cont, {verse, [note | notes]}}

  defp chunk_verse({name, _, _, line}, _acc, stem) do
    raise ArgumentError, "sblgnt apparatus #{stem}.xml line #{line}: unexpected <#{name}>"
  end

  defp verse_units({verse, notes}, book, names, stem) do
    label = Xml.text(verse)

    {chapter, number} =
      case Regex.run(regex(~S"^(.+) ([0-9]+):([0-9]+)$"), label) do
        [_, name, chapter, number] when is_map_key(names, name) ->
          if names[name] != book, do: raise(ArgumentError, "#{stem}.xml: #{label} in #{book}")
          {String.to_integer(chapter), String.to_integer(number)}

        _ ->
          raise ArgumentError, "sblgnt apparatus #{stem}.xml: verse #{inspect(label)}"
      end

    if notes == [],
      do: raise(ArgumentError, "sblgnt apparatus #{stem}.xml: #{label} has no notes")

    notes
    |> Enum.with_index(1)
    |> Enum.map(fn {{"note", _, _, line} = note, unit} ->
      raw = Xml.text(note)

      base = %{
        reference: "#{book}.#{chapter}.#{number}",
        book: book,
        chapter: chapter,
        verse: number,
        unit: unit,
        note: raw,
        file: stem,
        line: line
      }

      case parse_note(raw, chapter, number) do
        {:ok, parsed} ->
          Map.merge(base, Map.put(parsed, :parsed, true))

        {:error, reason} ->
          Map.merge(base, %{
            parsed: false,
            reason: reason,
            verses: nil,
            lemma: nil,
            lemma_sigla: nil,
            variants: nil
          })
      end
    end)
  end

  @doc """
  One apparatus note parsed: `{:ok, %{verses, lemma, lemma_sigla,
  variants}}` (`verses` the span a note names, '22–23', else nil), or
  `{:error, reason}`. A note starts with its verse's number (the verse's
  first unit; `1:15` at a chapter's start) or with `•` (a further unit).
  """
  @spec parse_note(String.t(), integer(), integer()) :: {:ok, map()} | {:error, String.t()}
  def parse_note(raw, chapter, verse) do
    note = raw |> String.replace("\u00A0", " ") |> String.trim()

    with {:ok, verses, body} <- note_prefix(note, chapter, verse),
         [lemma, variants] <- String.split(body, "]"),
         {:ok, [{lemma, lemma_sigla}]} <- readings(lemma),
         {:ok, variants} <- readings(variants) do
      {:ok,
       %{
         verses: verses,
         lemma: lemma,
         lemma_sigla: lemma_sigla,
         variants: Enum.map(variants, fn {text, sigla} -> %{text: text, sigla: sigla} end)
       }}
    else
      {:error, reason} -> {:error, reason}
      {:ok, [_ | _]} -> {:error, "more than one reading before ']'"}
      parts when is_list(parts) -> {:error, "#{length(parts) - 1} ']' separators, not one"}
    end
  end

  defp note_prefix("•" <> body, _chapter, _verse), do: {:ok, nil, String.trim(body)}

  defp note_prefix(note, chapter, verse) do
    case Regex.run(regex(~S"^(?:([0-9]+):)?([0-9]+)(?:–([0-9]+))? (.*)$"), note) do
      [_, c, v, through, body] ->
        cond do
          String.to_integer(v) != verse or (c != "" and String.to_integer(c) != chapter) ->
            {:error, "starts with another verse number"}

          through != "" ->
            {:ok, "#{v}–#{through}", body}

          true ->
            {:ok, nil, body}
        end

      nil ->
        {:error, "starts with neither the verse number nor •"}
    end
  end

  # Readings: words, then the sigla that support them; ';' after a siglum
  # ends a reading (a Greek ';' is a question mark and stays in the text);
  # one '.' may end the note. A reading may have no words (the lemma's text
  # with WH's double brackets, '] ⟦WH⟧').
  defp readings(text) do
    tokens = String.split(text)
    last = length(tokens) - 1

    tokens
    |> Enum.with_index()
    |> Enum.reduce_while({[], [], []}, &read_token(&1, &2, last))
    |> case do
      {:error, reason} -> {:error, reason}
      {done, [], []} -> close(done)
      {_done, _words, []} -> {:error, "a reading without sigla"}
      {done, words, sigla} -> close([{words, sigla} | done])
    end
  end

  defp read_token({token, index}, {done, words, sigla}, last) do
    case {siglum(token, index == last), sigla} do
      {{nil, _}, [_ | _]} -> {:halt, {:error, "words after the sigla: #{inspect(token)}"}}
      {{nil, _}, []} -> {:cont, {done, [token | words], []}}
      {{siglum, true}, _} -> {:cont, {[{words, [siglum | sigla]} | done], [], []}}
      {{siglum, false}, _} -> {:cont, {done, words, [siglum | sigla]}}
    end
  end

  defp siglum(token, last) do
    cond do
      token in @sigla ->
        {token, false}

      String.ends_with?(token, ";") and String.trim_trailing(token, ";") in @sigla ->
        {String.trim_trailing(token, ";"), true}

      last and String.ends_with?(token, ".") and String.trim_trailing(token, ".") in @sigla ->
        {String.trim_trailing(token, "."), false}

      true ->
        {nil, false}
    end
  end

  defp close([]), do: {:error, "no reading"}

  defp close(done) do
    readings =
      done
      |> Enum.reverse()
      |> Enum.map(fn {words, sigla} ->
        {words |> Enum.reverse() |> Enum.join(" "), Enum.reverse(sigla)}
      end)

    if Enum.any?(readings, fn {_, sigla} -> List.last(sigla) == "em" end),
      do: {:error, "'em' without the edition it belongs to"},
      else: {:ok, readings}
  end

  # --- HOTTP ------------------------------------------------------------------

  @doc """
  The HOTTP entries from `HOTTP.XML`: `%{entries, alternatives, verses,
  french}`, every English text field with its markup removed (`clean!/1`).
  `english` maps Hebrew numbering to English as for `samaritan/2`.
  """
  @spec hottp(binary(), (tuple() -> {integer(), integer()} | nil)) :: map()
  def hottp(xml, english) do
    {"HOTTP_Entries", _, _, _} = root = Xml.parse!("HOTTP.XML", xml)
    books = Books.all() |> Enum.take(39) |> Enum.map(&elem(&1, 0)) |> List.to_tuple()

    parsed = root |> Xml.elements() |> Enum.map(&hottp_entry(&1, books, english))

    %{
      entries: Enum.map(parsed, & &1.entry),
      alternatives: Enum.flat_map(parsed, & &1.alternatives),
      verses: Enum.flat_map(parsed, & &1.verses),
      french: parsed |> Enum.map(& &1.french) |> Enum.sum()
    }
  end

  defp hottp_entry({"HOTTP_Entry", %{"Id" => id}, _, line} = entry, books, english) do
    children = Xml.elements(entry)

    for {name, _, _, at} <- children, name not in @hottp_entry do
      raise ArgumentError, "HOTTP.XML line #{at}: unknown <#{name}> in entry #{id}"
    end

    field = fn name -> Enum.find(children, &match?({^name, _, _, _}, &1)) end

    alternatives =
      field.("Alternatives")
      |> Xml.elements()
      |> Enum.with_index(1)
      |> Enum.map(&hottp_alternative(&1, id))

    references = field.("References") |> Xml.elements() |> Enum.map(&Xml.text/1)

    %{
      entry: %{
        id: id,
        remark: field.("Remark") |> Xml.text() |> clean!(),
        suggestion: field.("Suggestion") |> Xml.text() |> clean!(),
        line: line
      },
      alternatives: Enum.map(alternatives, &elem(&1, 0)),
      verses: hottp_verses(id, references, books, english),
      french:
        Enum.count(children, &(elem(&1, 0) in @hottp_french)) +
          Enum.sum(Enum.map(alternatives, &elem(&1, 1)))
    }
  end

  defp hottp_entry({name, _, _, line}, _books, _english),
    do: raise(ArgumentError, "HOTTP.XML line #{line}: unexpected <#{name}>")

  defp hottp_alternative({{"Alternative", _, _, line} = alternative, position}, id) do
    children = Xml.elements(alternative)

    for {name, _, _, at} <- children, name not in @hottp_alternative do
      raise ArgumentError, "HOTTP.XML line #{at}: unknown <#{name}> in entry #{id} (line #{line})"
    end

    field = fn name -> Enum.find(children, &match?({^name, _, _, _}, &1)) end
    text = fn name -> if element = field.(name), do: element |> Xml.text() |> clean!() end
    rating = text.("Rating")

    renderings =
      for {"Version", _, _, _} = version <- Xml.elements(field.("Versions")) do
        [{"Text", _, _, _} = name, {"Content", _, _, _} = content] = Xml.elements(version)
        %{version: Xml.text(name), text: content |> Xml.text() |> clean!()}
      end

    factors = for factor <- Xml.elements(field.("Factors")), do: factor |> Xml.text() |> clean!()

    {%{
       entry_id: id,
       position: position,
       hebrew: text.("Source"),
       rating: rating,
       grade: grade(rating),
       factors: factors,
       literal: text.("Literal"),
       renderings: renderings
     }, Enum.count(children, &(elem(&1, 0) in @hottp_french))}
  end

  # The rating's letter: 'B (Qere)' → B, 'c' → C; '?' and none → nil.
  defp grade(nil), do: nil

  defp grade(rating) do
    case rating |> String.first() |> String.upcase() do
      letter when letter in ~w(A B C D) -> letter
      _ -> nil
    end
  end

  defp hottp_verses(id, references, books, english) do
    references
    |> Enum.map(&hottp_reference(&1, id, books))
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.uniq_by(fn [{key, _} | _] -> key end)
    |> Enum.map(fn [{{book, chapter, verse} = key, _} | _] = segments ->
      {{c, v}, mapped} =
        case english.(key) do
          nil -> {{chapter, verse}, 0}
          english -> {english, 1}
        end

      %{
        reference: "#{book}.#{c}.#{v}",
        entry_id: id,
        book: book,
        chapter: c,
        verse: v,
        source_reference: "#{book}.#{chapter}.#{verse}",
        mt_verse: mapped,
        segments: Enum.map(segments, &elem(&1, 1))
      }
    end)
  end

  defp hottp_reference(reference, id, books) do
    case Regex.run(regex(~S"^([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{5})$"), reference) do
      [_ | parts] ->
        [book, chapter, verse, segment] = Enum.map(parts, &String.to_integer/1)

        if book not in 1..39 do
          raise ArgumentError, "HOTTP.XML entry #{id}: book #{book} in #{reference}"
        end

        {{elem(books, book - 1), chapter, verse}, segment}

      nil ->
        raise ArgumentError, "HOTTP.XML entry #{id}: reference #{inspect(reference)}"
    end
  end

  @doc """
  A HOTTP English field with its markup removed: the `<span
  class="hebrew">` around Hebrew in remarks and the `\\heb … \\heb*` and
  `\\grk … \\grk*` markers, whitespace collapsed; nil when empty. Any other
  tag or backslash marker (a backslash before a letter) stops the build; a
  backslash the report uses between alternative forms (`קֵן \\ קֵין`) stays.
  """
  @spec clean!(String.t()) :: String.t() | nil
  def clean!(text) do
    cleaned =
      text
      |> then(&Regex.replace(regex(~S'<span class="hebrew">(.*?)</span>'), &1, "\\1"))
      |> then(&Regex.replace(regex(~S"\\(heb|grk) (.*?)\\\1\*"), &1, "\\2"))

    stripped = Enum.reduce(@hottp_literal_backslashes, cleaned, &String.replace(&2, &1, ""))

    cond do
      Regex.match?(regex(~S"</?[A-Za-z]"), cleaned) ->
        raise ArgumentError, "HOTTP: unknown markup in #{inspect(text)}"

      Regex.match?(regex(~S"\\[A-Za-z]"), stripped) ->
        raise ArgumentError, "HOTTP: unknown marker in #{inspect(text)}"

      true ->
        case cleaned |> String.split() |> Enum.join(" ") do
          "" -> nil
          collapsed -> collapsed
        end
    end
  end

  @doc """
  The rating glossary of `HOTTP-RATINGS-EN.HTML` (`<b>A</b> - meaning`):
  exactly A, B, C and D, else it raises.
  """
  @spec ratings(binary()) :: [%{grade: String.t(), meaning: String.t()}]
  def ratings(html) do
    rows =
      regex(~S'<li><p class="c1"><b>([A-D])</b> - (.*?)</p></li>')
      |> Regex.scan(html, capture: :all_but_first)
      |> Enum.map(fn [grade, meaning] -> %{grade: grade, meaning: html_text(meaning)} end)

    if Enum.map(rows, & &1.grade) != ~w(A B C D) do
      raise ArgumentError, "HOTTP-RATINGS-EN.HTML: ratings #{inspect(Enum.map(rows, & &1.grade))}"
    end

    rows
  end

  @doc """
  The factor glossary of `HOTTP-FACTORS-EN.HTML`: each `<h3>N. name =
  Factor K.</h3>` and the paragraph after it, under its `<h2>` section
  (evaluation, modification, additional); exactly factors 1–15, else it
  raises.
  """
  @spec factors(binary()) :: [map()]
  def factors(html) do
    sections =
      regex(~S'<h2 class="c1">[A-C]\. (.*?)</h2>')
      |> Regex.scan(html, return: :index, capture: :all_but_first)
      |> Enum.map(fn [{at, length}] -> {at, binary_part(html, at, length)} end)

    rows =
      regex(~S'<h3 class="c1">[0-9]+\. (.*?) = Factor ([0-9]+)\.</h3>\s*<p class="c1">(.*?)</p>')
      |> Regex.scan(html, return: :index, capture: :all_but_first)
      |> Enum.map(fn [{at, _} = name, number, explanation] ->
        {_, section} = sections |> Enum.filter(&(elem(&1, 0) < at)) |> List.last()

        %{
          number: html |> part(number) |> String.to_integer(),
          kind: section,
          name: html |> part(name) |> html_text(),
          explanation: html |> part(explanation) |> html_text()
        }
      end)

    if Enum.map(rows, & &1.number) != Enum.to_list(1..15) do
      raise ArgumentError,
            "HOTTP-FACTORS-EN.HTML: factors #{inspect(Enum.map(rows, & &1.number))}"
    end

    rows
  end

  defp part(html, {at, length}), do: binary_part(html, at, length)

  defp html_text(text) do
    if Regex.match?(regex(~S"<|&(?!quot;)"), text) do
      raise ArgumentError, "HOTTP glossary: unexpected markup in #{inspect(text)}"
    end

    text |> String.replace("&quot;", "\"") |> String.split() |> Enum.join(" ")
  end

  # --- Versification ----------------------------------------------------------

  @doc """
  The core pack's New Testament verses as `{book, chapter, verse}`, from
  rows of `[reference, book, chapter, verse]`: the SBLGNT's numbering must
  be one of them.
  """
  @spec nt_verses([list()]) :: MapSet.t()
  def nt_verses(rows) do
    nt = @sblgnt_books |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    for [_reference, book, chapter, verse] <- rows,
        book in nt,
        into: MapSet.new(),
        do: {book, chapter, verse}
  end

  @doc "`english_numbering/1` of `Bezalel.Data.Scrolls`, for the Hebrew-numbered sources."
  @spec english_numbering([String.t()]) :: (tuple() -> {integer(), integer()} | nil)
  def english_numbering(references), do: Scrolls.english_numbering(references)

  # --- Report -----------------------------------------------------------------

  @doc "The import report: sources, counts, what was mapped, refused or dropped."
  @spec report(map()) :: String.t()
  def report(r) do
    sp_mapped = Enum.count(r.sp.verses, &(&1.mt_verse == 1))

    hottp_unmapped =
      for %{mt_verse: 0} = v <- r.hottp.verses, do: "#{v.source_reference} (#{v.entry_id})"

    parsed = Enum.count(r.apparatus.units, & &1.parsed)
    rated = Enum.count(r.hottp.alternatives, & &1.rating)

    [
      "# The witnesses pack",
      "",
      "Sources:",
      Enum.map(r.sources, &"- #{&1}\n"),
      "",
      "## The Samaritan Pentateuch (sp_verses, CC BY-NC 4.0)",
      "#{length(r.sp.verses)} verses; #{sp_mapped} filed under the core pack's English reference " <>
        "(#{Enum.count(r.sp.verses, &(&1.mt_verse == 1 and &1.reference != &1.source_reference))} " <>
        "renumbered); #{length(r.sp.unmapped)} with no core verse, kept under the dataset's number:",
      list(r.sp.unmapped),
      "Notes: " <>
        Enum.map_join(
          for(%{note: n} = v when is_binary(n) <- r.sp.verses, do: "#{v.reference}: #{n}"),
          "; ",
          & &1
        ),
      "Core Torah verses the dataset lacks (#{length(r.sp_missing)}):",
      list(r.sp_missing),
      "",
      "## The SBLGNT (sblgnt_verses, CC BY 4.0)",
      "#{length(r.sblgnt)} verses; not core verses: #{length(r.sblgnt_extra)}",
      list(r.sblgnt_extra),
      "Core New Testament verses the SBLGNT doesn't print (#{length(r.sblgnt_missing)}):",
      list(r.sblgnt_missing),
      "",
      "## The SBLGNT apparatus (sblgnt_apparatus, CC BY 4.0)",
      "#{length(r.apparatus.units)} notes; #{parsed} parsed into variation units; " <>
        "#{length(r.apparatus.refused)} kept raw, unparsed:",
      Enum.map(r.apparatus.refused, &"- #{&1.reference} unit #{&1.unit}: #{&1.reason}\n"),
      "Units spanning verses: #{Enum.count(r.apparatus.units, & &1[:verses])}",
      "",
      "## HOTTP (hottp_*, CC BY-SA 4.0)",
      "#{length(r.hottp.entries)} entries, #{length(r.hottp.alternatives)} alternatives " <>
        "(#{rated} rated), #{length(r.hottp.verses)} entry-verse rows of " <>
        "#{r.hottp.verses |> Enum.uniq_by(& &1.reference) |> length()} verses",
      "Renumbered to English: #{Enum.count(r.hottp.verses, &(&1.mt_verse == 1 and &1.reference != &1.source_reference))}; " <>
        "with no core verse (#{length(hottp_unmapped)}):",
      list(hottp_unmapped),
      "Dropped: #{r.hottp.french} French fields (Remark-FR, SuggestionFR, LiteralFR).",
      "Ratings: " <>
        inspect(
          r.hottp.alternatives
          |> Enum.map(& &1.rating)
          |> Enum.reject(&is_nil/1)
          |> Enum.frequencies()
          |> Enum.sort()
        ),
      "Factors cited: " <>
        inspect(
          r.hottp.alternatives
          |> Enum.flat_map(& &1.factors)
          |> Enum.frequencies()
          |> Enum.sort()
        ),
      "Glossaries: #{length(r.ratings)} ratings, #{length(r.factors)} factors",
      ""
    ]
    |> Enum.map_join(&if(is_binary(&1), do: &1 <> "\n", else: IO.iodata_to_binary(&1)))
  end

  defp list([]), do: ["  (none)\n"]

  defp list(items),
    do: Enum.map(Enum.chunk_every(items, 10), &("  " <> Enum.join(&1, " ") <> "\n"))

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
