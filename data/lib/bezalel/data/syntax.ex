defmodule Bezalel.Data.Syntax do
  @moduledoc """
  Clear-Bible MACULA's lowfat syntax trees (`WLC/lowfat/*-lowfat.xml` of
  macula-hebrew, one per chapter; `SBLGNT/lowfat/NN-book.xml` of
  macula-greek, one per book) → the `syntax` pack's rows: for every verse,
  in the packs' English numbering, the clauses of the sentences that touch
  it.

  **What is read.** Of each word (`<w>`): its text and `after` (the space
  or punctuation after it), `ref` (book chapter:verse!word), `role`,
  Strong's number (`strongnumberx` in Hebrew, `strong` in Greek), English
  gloss (Hebrew: `english`, Cherith's, else `gloss`; Greek: `gloss`, the
  Berean Interlinear's, else `english`, Cherith's) and `lemma`. Of each word
  group (`<wg>`, Hebrew `<c>`): `class` (`cl` is a clause), `rule` (or
  `Rule`) and `role`. Nothing else: in particular not the UBS attributes
  MACULA marks "Used with permission" (Hebrew `sdbh`, `lexdomain`,
  `coredomain`, `contextualdomain`; Greek `ln`, `domain`), which are not
  under its CC BY 4.0 licence. `attribute_counts` in the parse result lists
  every attribute seen, for the report.

  **The shape.** A sentence becomes a list of clauses (each `wg class="cl"`)
  in document order; a clause's parts are its words grouped by the role
  they fill in it (`s`, `v`, `o`, …: the nearest role between the word and
  its clause; a word with none, a conjunction, is a part without a role),
  and a clause inside a clause is a reference from the part it fills to the
  inner clause. A clause made of nothing but other clauses (a clause
  complex, `ClCl`) is dissolved into them. For a verse, the clauses shown
  are those with a word of their own in the verse and their enclosing
  clauses; the sentence's other clauses are counted, not stored; a word
  outside the verse keeps only its text, marked with its verse.

  The row's `clauses` value is JSON: a list of sentences, each
  `%{"c" => clauses, "x" => clauses left out, "v" => the sentence's span
  when it crosses the verse, "r" => the edition's own verse number when it
  differs}`; a clause is `[depth, role, rule, parts]`, a part `[role,
  items]`, and an item `[text, strong, gloss, lemma]` (a word of the verse),
  `[verse, text]` (words outside it), `[verse]` (a clause outside it) or an
  integer (the 1-based number of a clause shown, in the same sentence).
  Verse labels are `chapter:verse` in the packs' English numbering.
  """

  alias Bezalel.Data.{Books, Net}

  @editions %{
    "hebrew" => %{edition: "WLC", language: "Hebrew", prefix: "H"},
    "greek" => %{edition: "SBLGNT", language: "Greek", prefix: "G"}
  }

  # Attributes of a word the pack keeps (the rest are counted, not read).
  @word_attributes ~w(ref role after strongnumberx strong english gloss lemma)
  @group_attributes ~w(class rule Rule role)
  @not_licensed ~w(sdbh lexdomain coredomain contextualdomain ln domain)

  # The code and data that decide the pack's rows, relative to data/.
  @build_inputs ~w(
    lib/bezalel/data/syntax.ex lib/bezalel/data/syntax_pack.ex
    lib/bezalel/data/pack.ex lib/bezalel/data/books.ex
    lib/mix/tasks/bezalel.data.syntax.ex
  )

  # At most this many words of a run outside the verse keep their text.
  @outside_words 8

  @type word :: %{
          ref: {String.t(), pos_integer(), non_neg_integer()},
          role: String.t() | nil,
          text: String.t(),
          strong: String.t() | nil,
          gloss: String.t() | nil,
          lemma: String.t() | nil
        }

  @doc ~s(The editions: "hebrew" and "greek", with edition, language and Strong's prefix.)
  @spec editions() :: map()
  def editions, do: @editions

  @doc "The attributes MACULA marks 'Used with permission' (UBS), never imported."
  @spec not_licensed() :: [String.t()]
  def not_licensed, do: @not_licensed

  @doc """
  One checksum of the files that decide the pack's rows (`@build_inputs`),
  recorded in `pack_meta.build_sha256`.
  """
  @spec build_digest() :: String.t()
  def build_digest do
    root = Path.expand("../../..", __DIR__)

    @build_inputs
    |> Enum.map(fn path ->
      sha256 = :crypto.hash(:sha256, File.read!(Path.join(root, path)))
      [path, ?\t, Base.encode16(sha256, case: :lower), ?\n]
    end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "The STEP book code of a MACULA (USFM) book code ('GEN', '1SA', 'JHN'), or nil."
  @spec book(String.t()) :: String.t() | nil
  def book(code) do
    key = {__MODULE__, :books}

    books =
      case :persistent_term.get(key, nil) do
        nil ->
          books = Map.new(Books.all(), fn {step, _, _} -> {String.upcase(step), step} end)
          :persistent_term.put(key, books)
          books

        books ->
          books
      end

    Map.get(books, code)
  end

  @doc """
  `{language, name} => sha256` of every file `pin` (pins.json → `macula`)
  names, from the file list it points to (`macula_files.json`).
  """
  @spec pinned_files(map()) :: %{{String.t(), String.t()} => String.t()}
  def pinned_files(pin) do
    listed = Path.expand("../../../#{pin["files"]}", __DIR__) |> File.read!() |> Jason.decode!()

    for language <- ~w(hebrew greek), {name, sha256} <- listed[language], into: %{} do
      {{language, name}, sha256}
    end
  end

  @doc """
  One checksum of the pinned files (`pinned_files/1`), as
  `pack_meta.macula_sha256` records it: sha256 over `language/name<TAB>sha256<LF>`, sorted.
  """
  @spec source_digest(map()) :: String.t()
  def source_digest(shas) do
    shas
    |> Enum.map(fn {{language, name}, sha256} -> {"#{language}/#{name}", sha256} end)
    |> Enum.sort()
    |> Net.digest()
  end

  @doc "The two repos at their pinned commits, as `pack_meta.macula_source` records them."
  @spec source(map()) :: String.t()
  def source(pin),
    do: Enum.map_join(~w(hebrew greek), " ", &"#{pin[&1]["repo"]}/tree/#{pin[&1]["commit"]}")

  @doc """
  The edition → English verse map from a core pack's `verses` rows
  `[reference, book, chapter, verse]`: a split reference ('Psa.3.0(3.1)')
  maps the edition's verse in parentheses (the Hebrew Bible's numbering,
  which the WLC and the SBLGNT follow) to the row's chapter and verse; any
  other row ('Gen.1.1', and the NT's '3Jn.1.15[1.14]' and 'Jhn.7.53{8.1}')
  maps its own chapter and verse to themselves. A verse the core pack splits
  between two English verses maps to both ('Psa.23.0(23.1)' beside
  'Psa.23.1': Hebrew 23:1 is English 23:0 and 23:1). Returns a function of
  `{book, chapter, verse}` giving the English `{chapter, verse}`s in order,
  [] for a verse the core pack lacks.
  """
  @spec english_numbering([[term()]]) :: (tuple() -> [{integer(), integer()}])
  def english_numbering(rows) do
    split = :binary.compile_pattern("(")

    map =
      rows
      |> Enum.map(fn [reference, book, chapter, verse] ->
        source =
          case :binary.split(reference, split) do
            [_, numbers] -> source(book, numbers)
            [_plain] -> {book, chapter, verse}
          end

        {source, {chapter, verse}}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {source, english} -> {source, english |> Enum.uniq() |> Enum.sort()} end)

    &Map.get(map, &1, [])
  end

  defp source(book, numbers) do
    [chapter, verse] = numbers |> String.trim_trailing(")") |> String.split(".")
    {book, String.to_integer(chapter), String.to_integer(verse)}
  end

  # --- Parsing ------------------------------------------------------------------

  @doc """
  Parses one lowfat file of `language` ("hebrew" | "greek"): its sentences,
  each a list of `{:wg, attributes, children}` and `{:w, word()}` trees,
  and the count of every attribute seen on `<w>` and `<wg>`.
  """
  @spec parse(binary(), String.t()) :: %{sentences: [list()], attribute_counts: map()}
  def parse(xml, language) when is_map_key(@editions, language) do
    state = %{stack: [], sentences: [], counts: %{}, language: language, skip: 0}

    case :xmerl_sax_parser.stream(xml, event_fun: &event/3, event_state: state) do
      {:ok, state, _rest} ->
        %{sentences: Enum.reverse(state.sentences), attribute_counts: state.counts}

      # An exception in event/3 (an element MACULA's files don't have).
      {:fatal_error, %ArgumentError{} = error} ->
        raise error

      {error, location, reason, _tags, _state} ->
        raise ArgumentError, "XML #{error} at #{inspect(location)}: #{inspect(reason)}"
    end
  end

  defp event({:startElement, _uri, name, _qname, attributes}, _location, state) do
    element(List.to_string(name), attributes, state)
  end

  defp event({:characters, chars}, _location, %{stack: [{:w, attrs, text} | rest]} = state),
    do: %{state | stack: [{:w, attrs, [text | List.to_string(chars)]} | rest]}

  defp event({:endElement, _uri, name, _qname}, _location, state),
    do: close(List.to_string(name), state)

  defp event(_event, _location, state), do: state

  # Inside <p> (the verse text and milestones): nothing is read.
  defp element(_name, _attributes, %{skip: skip} = state) when skip > 0,
    do: %{state | skip: skip + 1}

  defp element("p", _attributes, state), do: %{state | skip: 1}
  defp element("sentence", _attributes, state), do: %{state | stack: [{:sentence, []}]}

  defp element(name, attributes, %{stack: [_ | _]} = state) when name in ["w", "wg", "c"] do
    attrs = Map.new(attributes, fn {_, _, k, v} -> {List.to_string(k), List.to_string(v)} end)
    counts = Enum.reduce(Map.keys(attrs), state.counts, &Map.update(&2, &1, 1, fn n -> n + 1 end))

    node =
      if name == "w",
        do: {:w, Map.take(attrs, @word_attributes), ""},
        else: {:wg, Map.take(attrs, @group_attributes), []}

    %{state | stack: [node | state.stack], counts: counts}
  end

  defp element(name, _attributes, %{stack: [_ | _]}),
    do: raise(ArgumentError, "unknown element <#{name}> in a sentence")

  defp element(_name, _attributes, state), do: state

  defp close(_name, %{skip: skip} = state) when skip > 0, do: %{state | skip: skip - 1}

  defp close("sentence", %{stack: [{:sentence, children}]} = state),
    do: %{state | stack: [], sentences: [Enum.reverse(children) | state.sentences]}

  defp close("w", %{stack: [{:w, attrs, text} | rest]} = state),
    do: %{state | stack: attach(rest, word(attrs, IO.iodata_to_binary(text), state.language))}

  defp close(name, %{stack: [{:wg, attrs, children} | rest]} = state) when name in ["wg", "c"],
    do: %{state | stack: attach(rest, {:wg, attrs, Enum.reverse(children)})}

  defp close(_name, state), do: state

  defp attach([{:sentence, children} | rest], node), do: [{:sentence, [node | children]} | rest]
  defp attach([{:wg, attrs, children} | rest], node), do: [{:wg, attrs, [node | children]} | rest]

  defp word(attrs, text, language) do
    [code, place] = String.split(attrs["ref"], " ", parts: 2)
    [chapter, verse] = place |> String.split("!") |> hd() |> String.split(":")

    book =
      book(code) || raise ArgumentError, "unknown book #{inspect(code)} in #{attrs["ref"]}"

    {gloss, strong} =
      case language do
        "hebrew" -> {present(attrs["english"]) || present(attrs["gloss"]), attrs["strongnumberx"]}
        "greek" -> {present(attrs["gloss"]) || present(attrs["english"]), attrs["strong"]}
      end

    {:w,
     %{
       ref: {book, String.to_integer(chapter), String.to_integer(verse)},
       role: attrs["role"],
       text: String.trim(text) <> separator(attrs["after"]),
       strong: strong(strong, @editions[language].prefix),
       gloss: gloss,
       lemma: present(attrs["lemma"])
     }}
  end

  # What follows a word: nothing within a Hebrew word (a prefix morpheme
  # has no `after`); after a maqqef nothing more; else MACULA's punctuation
  # (Greek ',' '·' '.', Hebrew '׃' '׀', or none) and a space.
  defp separator(nil), do: ""

  defp separator(following) do
    following = String.trim(following)
    if String.ends_with?(following, "־"), do: following, else: following <> " "
  end

  defp present(nil), do: nil
  defp present(value), do: if(String.trim(value) == "", do: nil, else: value)

  @doc """
  A MACULA Strong's number in Bezalel's form: `prefix` and four digits
  ('0430' → 'H0430', '976' → 'G0976'). MACULA's own letter suffixes
  ('0871a') are dropped: they are not STEPBible's sense letters. Nil when
  there is no number.
  """
  @spec strong(String.t() | nil, String.t()) :: String.t() | nil
  def strong(nil, _prefix), do: nil

  def strong(value, prefix) do
    case Integer.parse(String.trim(value)) do
      {number, _suffix} -> prefix <> String.pad_leading(Integer.to_string(number), 4, "0")
      :error -> nil
    end
  end

  # --- Clauses ------------------------------------------------------------------

  @doc """
  A sentence's clauses, in document order: `%{id, parent, role, rule,
  parts}` with `parts` a list of `{role, items}` (`{:w, word()}` or `{:c,
  id}`), and the words outside every clause as a clause with rule nil
  (`:loose`, parent nil). Returns `{clauses, notes}`, `notes` counting the
  role values not read (`:bad_roles`) and roles inside a constituent's
  role (`:inner_roles`).
  """
  @spec clauses(list()) :: {[map()], map()}
  def clauses(sentence) do
    state = %{clauses: %{}, order: [], next: 1, notes: %{}}
    ctx = %{clause: nil, role: nil}
    state = Enum.reduce(sentence, state, &walk(&1, ctx, &2))

    clauses =
      state.order
      |> Enum.reverse()
      |> Enum.map(fn id ->
        clause = state.clauses[id]
        %{clause | parts: clause.parts |> Enum.reverse() |> Enum.map(&reverse_part/1)}
      end)
      |> dissolve_complexes()

    {clauses, state.notes}
  end

  defp reverse_part({role, items}), do: {role, Enum.reverse(items)}

  # A clause; and a group at the top of the sentence (MACULA wraps clauses
  # joined by conjunctions in one), shown as a clause so its words keep
  # their place between the clauses.
  defp walk({:wg, attrs, children}, %{clause: parent} = ctx, state)
       when parent == nil or :erlang.map_get("class", attrs) == "cl" do
    {own, state} = role(attrs["role"], state)
    id = state.next

    clause = %{
      id: id,
      parent: ctx.clause,
      role: own || ctx.role,
      rule: attrs["rule"] || attrs["Rule"],
      parts: []
    }

    state = %{
      state
      | clauses: Map.put(state.clauses, id, clause),
        order: [id | state.order],
        next: id + 1
    }

    state = if ctx.clause, do: append(state, ctx.clause, ctx.role, {:c, id}), else: state
    Enum.reduce(children, state, &walk(&1, %{clause: id, role: nil}, &2))
  end

  defp walk({:wg, attrs, children}, ctx, state) do
    {role, state} = inner_role(attrs["role"], ctx.role, state)
    Enum.reduce(children, state, &walk(&1, %{ctx | role: role}, &2))
  end

  defp walk({:w, word}, ctx, state) do
    {role, state} = inner_role(word.role, ctx.role, state)
    {clause, state} = loose(ctx.clause, state)
    append(state, clause, role, {:w, %{word | role: role}})
  end

  # A word outside every clause goes into the sentence's one :loose clause.
  defp loose(nil, %{clauses: %{loose: _}} = state), do: {:loose, state}

  defp loose(nil, state) do
    clause = %{id: :loose, parent: nil, role: nil, rule: nil, parts: []}

    {:loose,
     %{state | clauses: Map.put(state.clauses, :loose, clause), order: [:loose | state.order]}}
  end

  defp loose(id, state), do: {id, state}

  # The outer role wins: a role inside a constituent of the same clause
  # (no clause between) is counted, not used.
  defp inner_role(value, nil, state), do: role(value, state)

  defp inner_role(value, outer, state) do
    case role(value, state) do
      {nil, state} -> {outer, state}
      {^outer, state} -> {outer, state}
      {_inner, state} -> {outer, note(state, :inner_roles)}
    end
  end

  # MACULA's roles; '' is none, and its 'err_…' values (a few Greek
  # groups its conversion flagged) are counted and read as none.
  defp role(nil, state), do: {nil, state}
  defp role("", state), do: {nil, state}

  defp role("err" <> _rest, state), do: {nil, note(state, :bad_roles)}

  defp role(value, state), do: {value, state}

  defp note(state, key), do: %{state | notes: Map.update(state.notes, key, 1, &(&1 + 1))}

  defp append(state, id, role, item) do
    update_in(state.clauses[id].parts, fn
      [{^role, items} | rest] -> [{role, [item | items]} | rest]
      parts -> [{role, [item]} | parts]
    end)
  end

  # A clause of nothing but clauses (a clause complex) is replaced, in its
  # parent's part, by its clauses, which take its parent and, when they
  # have none of their own, its role.
  defp dissolve_complexes(clauses) do
    case Enum.find(clauses, &complex?/1) do
      nil -> clauses |> Enum.reject(&complex?/1)
      complex -> clauses |> dissolve(complex) |> dissolve_complexes()
    end
  end

  defp complex?(%{id: :loose}), do: false

  defp complex?(%{parts: parts}),
    do: Enum.all?(parts, fn {_role, items} -> Enum.all?(items, &match?({:c, _}, &1)) end)

  defp dissolve(clauses, %{id: id} = complex) do
    inner = for {_role, items} <- complex.parts, {:c, child} <- items, do: child

    clauses
    |> Enum.reject(&(&1.id == id))
    |> Enum.map(fn clause ->
      cond do
        clause.parent == id ->
          %{clause | parent: complex.parent, role: clause.role || complex.role}

        clause.id == complex.parent ->
          %{clause | parts: Enum.map(clause.parts, &replace_ref(&1, id, inner))}

        true ->
          clause
      end
    end)
  end

  defp replace_ref({role, items}, id, inner) do
    {role,
     Enum.flat_map(items, fn item -> if item == {:c, id}, do: inner_refs(inner), else: [item] end)}
  end

  defp inner_refs(ids), do: Enum.map(ids, &{:c, &1})

  # --- A verse's view -----------------------------------------------------------

  @doc """
  The view of one sentence (`clauses/1`'s clauses) for the verse whose
  source verses (`{book, chapter, verse}` in the edition's numbering) are
  `in_verse`, `english` mapping source verses to English `{chapter,
  verse}`: the stored sentence map (see the moduledoc). Nil when no clause
  has a word in the verse.
  """
  @spec view([map()], MapSet.t(), (tuple() -> [{integer(), integer()}])) :: map() | nil
  def view(clauses, in_verse, english) do
    by_id = Map.new(clauses, &{&1.id, &1})
    words = Map.new(clauses, &{&1.id, own_words(&1)})

    touching =
      for %{id: id} <- clauses,
          Enum.any?(words[id], &MapSet.member?(in_verse, &1.ref)),
          do: id

    shown = touching |> Enum.flat_map(&lineage(&1, by_id)) |> MapSet.new()

    if MapSet.size(shown) == 0 do
      nil
    else
      shown_order = Enum.filter(clauses, &MapSet.member?(shown, &1.id))
      numbers = shown_order |> Enum.with_index(1) |> Map.new(fn {c, n} -> {c.id, n} end)
      all_refs = clauses |> Enum.flat_map(&words[&1.id]) |> Enum.map(& &1.ref)

      context = %{
        in_verse: in_verse,
        english: english,
        numbers: numbers,
        by_id: by_id,
        words: words
      }

      rendered =
        Enum.map(shown_order, fn clause ->
          [depth(clause, by_id), clause.role, clause.rule, parts(clause, context)]
        end)

      %{"c" => rendered}
      |> put_unless("x", length(clauses) - length(shown_order), 0)
      |> put_unless("v", span(all_refs, in_verse, english), nil)
    end
  end

  defp put_unless(map, _key, empty, empty), do: map
  defp put_unless(map, key, value, _empty), do: Map.put(map, key, value)

  defp own_words(clause), do: for({_role, items} <- clause.parts, {:w, word} <- items, do: word)

  defp lineage(nil, _by_id), do: []
  defp lineage(id, by_id), do: [id | lineage(by_id[id].parent, by_id)]

  defp depth(%{parent: nil}, _by_id), do: 0
  defp depth(%{parent: parent}, by_id), do: 1 + depth(by_id[parent], by_id)

  # The sentence's span, when it has words outside the verse.
  defp span(refs, in_verse, english) do
    if Enum.all?(refs, &MapSet.member?(in_verse, &1)), do: nil, else: label(refs, english)
  end

  defp parts(clause, context) do
    Enum.map(clause.parts, fn {role, items} -> [role, items(items, context)] end)
  end

  defp items(items, context) do
    items
    |> Enum.chunk_by(&item_kind(&1, context))
    |> Enum.flat_map(fn [first | _] = run -> run(item_kind(first, context), run, context) end)
  end

  # A run of items of one kind: words of the verse, words outside it (one
  # item: their verse and text), clauses shown, clauses outside the verse.
  defp run(:in, run, _context), do: for({:w, w} <- run, do: [w.text, w.strong, w.gloss, w.lemma])

  defp run(:out, run, context) do
    refs = for {:w, w} <- run, do: w.ref
    {kept, cut} = Enum.split(run, @outside_words)
    text = kept |> Enum.map_join("", fn {:w, w} -> w.text end) |> String.trim()
    [[label(refs, context.english), if(cut == [], do: text, else: text <> " …")]]
  end

  defp run({:clause, :shown}, run, context), do: for({:c, id} <- run, do: context.numbers[id])

  defp run({:clause, :outside}, run, context),
    do: for({:c, id} <- run, do: [label(clause_refs(id, context), context.english)])

  defp item_kind({:w, word}, context),
    do: if(MapSet.member?(context.in_verse, word.ref), do: :in, else: :out)

  defp item_kind({:c, id}, context),
    do: {:clause, if(Map.has_key?(context.numbers, id), do: :shown, else: :outside)}

  # Every word of clause `id` and the clauses inside it.
  defp clause_refs(id, context) do
    inner = for {_role, items} <- context.by_id[id].parts, {:c, child} <- items, do: child
    Enum.map(context.words[id], & &1.ref) ++ Enum.flat_map(inner, &clause_refs(&1, context))
  end

  @doc "'1:2' or '1:2–3' or '1:31–2:1' for `refs` in English numbering."
  @spec label([tuple()], (tuple() -> [{integer(), integer()}])) :: String.t()
  def label(refs, english) do
    places =
      refs
      |> Enum.map(fn {_book, chapter, verse} = ref ->
        case english.(ref) do
          [first | _] -> first
          [] -> {chapter, verse}
        end
      end)
      |> Enum.sort()

    case {List.first(places), List.last(places)} do
      {same, same} -> place(same)
      {{chapter, first}, {chapter, last}} -> "#{chapter}:#{first}–#{last}"
      {first, last} -> place(first) <> "–" <> place(last)
    end
  end

  defp place({chapter, verse}), do: "#{chapter}:#{verse}"

  # --- Rows ---------------------------------------------------------------------

  @doc """
  The rows of one parsed file (`parse/2`'s sentences) of `language` at
  `source_file` (its path in the repo): `{english_key, sentence_view,
  source_verse, source_file}` for each English verse each sentence
  touches, in order, and the clause notes, summed. `english_key` is
  `{book, chapter, verse}` in English numbering; a source verse the core
  pack lacks is returned in `unmapped`.
  """
  @spec rows([list()], String.t(), (tuple() -> [{integer(), integer()}])) :: map()
  def rows(sentences, source_file, english) do
    results = Enum.map(sentences, &sentence_rows(&1, source_file, english))

    %{
      rows: Enum.flat_map(results, & &1.rows),
      unmapped: Enum.flat_map(results, & &1.unmapped),
      notes:
        results
        |> Enum.map(& &1.notes)
        |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _key, a, b -> a + b end)),
      crossing: Enum.count(results, & &1.crossing)
    }
  end

  defp sentence_rows(sentence, source_file, english) do
    {clauses, notes} = clauses(sentence)
    refs = clauses |> Enum.flat_map(&own_words/1) |> Enum.map(& &1.ref) |> Enum.uniq()
    by_verse = by_english_verse(refs, english)

    rows =
      for {key, sources} <- Enum.sort_by(by_verse, fn {key, _} -> sort_key(key) end),
          view = view(clauses, MapSet.new(sources), english),
          view != nil do
        {key, put_source(view, key, sources, english), sources, source_file}
      end

    %{
      rows: rows,
      unmapped: Enum.filter(refs, &(english.(&1) == [])),
      notes: notes,
      crossing: map_size(by_verse) > 1
    }
  end

  # The source verses `refs` by the English verse(s) each maps to.
  defp by_english_verse(refs, english) do
    refs
    |> Enum.flat_map(fn {book, _, _} = ref ->
      for {chapter, verse} <- english.(ref), do: {{book, chapter, verse}, ref}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp sort_key({book, chapter, verse}), do: {Books.index(book), chapter, verse}

  # "r": the edition's verse number when it isn't the English one; "w":
  # the English verses an edition's verse is split between (it is shown
  # whole under each).
  defp put_source(view, {_book, chapter, verse}, sources, english) do
    sources = Enum.sort(sources)
    covered = sources |> Enum.flat_map(english) |> Enum.uniq()

    view =
      case sources do
        [{_, ^chapter, ^verse}] -> view
        _ -> Map.put(view, "r", Enum.map_join(sources, ", ", fn {_, c, v} -> "#{c}:#{v}" end))
      end

    if match?([_, _ | _], covered),
      do: Map.put(view, "w", places_label(covered)),
      else: view
  end

  defp places_label(covered) do
    case {List.first(covered), List.last(covered)} do
      {{chapter, a}, {chapter, b}} -> "#{chapter}:#{a}–#{b}"
      {first, last} -> place(first) <> "–" <> place(last)
    end
  end

  # --- Report -------------------------------------------------------------------

  @doc """
  The build report: what was read per edition, the rows, the core pack's
  verses without one (`core_verses`, English references), the source verses
  the core pack lacks, every attribute seen (imported or not, the UBS ones
  named) and the roles not read.
  """
  @spec report(map()) :: String.t()
  def report(%{source: source, parsed: parsed, verses: verses, core_verses: core_verses}) do
    by_language = Enum.group_by(parsed, & &1.language)
    stored = MapSet.new(verses, & &1.reference)
    without = Enum.reject(core_verses, &MapSet.member?(stored, &1))

    sections =
      for language <- ~w(hebrew greek) do
        edition_report(language, Map.get(by_language, language, []), verses)
      end

    sizes = Enum.map(verses, &byte_size(&1.clauses))
    largest = Enum.max_by(verses, &byte_size(&1.clauses), fn -> nil end)

    Enum.join(
      [
        "MACULA syntax pack build report",
        "Source: #{source}",
        "Rows: #{length(verses)} verses; clauses JSON #{Enum.sum(sizes)} bytes" <>
          if(largest,
            do: "; largest #{largest.reference} (#{byte_size(largest.clauses)} bytes)",
            else: ""
          ),
        "Core pack verses without a row (#{length(without)}; the editions lack them): " <>
          Enum.join(without, " ")
        | sections
      ],
      "\n\n"
    ) <> "\n"
  end

  defp edition_report(language, parsed, verses) do
    %{edition: edition} = @editions[language]
    rows = Enum.filter(verses, &(&1.edition == edition))

    counts =
      parsed
      |> Enum.map(& &1.attribute_counts)
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _, a, b -> a + b end))

    notes =
      parsed
      |> Enum.map(& &1.notes)
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _, a, b -> a + b end))

    unmapped = parsed |> Enum.flat_map(& &1.unmapped) |> Enum.uniq()
    sentences = rows |> Enum.flat_map(&Jason.decode!(&1.clauses))
    clauses = Enum.flat_map(sentences, & &1["c"])
    loose = Enum.count(clauses, &match?([0, nil, nil, _], &1))

    words =
      for [_, _, _, parts] <- clauses, [_, items] <- parts, [_, _, _, _] <- items, reduce: 0 do
        n -> n + 1
      end

    imported = @word_attributes ++ @group_attributes

    {kept, dropped} =
      counts |> Enum.sort() |> Enum.split_with(fn {name, _} -> name in imported end)

    ubs = for {name, n} <- dropped, name in @not_licensed, do: "#{name} (#{n})"
    other = for {name, n} <- dropped, name not in @not_licensed, do: "#{name} (#{n})"

    """
    == #{edition} (MACULA #{@editions[language].language}) ==
    Files: #{length(parsed)}; sentences: #{parsed |> Enum.map(& &1.sentences) |> Enum.sum()}, \
    #{parsed |> Enum.map(& &1.crossing) |> Enum.sum()} of them across verses
    Rows: #{length(rows)} verses; #{length(sentences)} sentence views, #{length(clauses)} clauses \
    shown (#{loose} groups of words outside any clause), #{words} words of their verse; \
    #{sentences |> Enum.map(&Map.get(&1, "x", 0)) |> Enum.sum()} clauses left out as outside their verse
    Source verses the core pack lacks (not imported): #{if unmapped == [], do: "none", else: unmapped |> Enum.map_join(", ", fn {b, c, v} -> "#{b}.#{c}.#{v}" end)}
    Roles not read: #{Map.get(notes, :bad_roles, 0)} 'err_…' values; #{Map.get(notes, :inner_roles, 0)} roles inside a constituent's role (the outer kept)
    Attributes read: #{Enum.map_join(kept, ", ", fn {name, n} -> "#{name} (#{n})" end)}
    Not imported, UBS data MACULA uses by permission (not CC BY): #{if ubs == [], do: "none seen", else: Enum.join(ubs, ", ")}
    Not imported, not needed: #{Enum.join(other, ", ")}\
    """
  end
end
