defmodule Bezalel.Data.Fathers do
  @moduledoc """
  The Apostolic Fathers → the `fathers` pack's rows.

  **Greek** (Latin where only a Latin version survives): jtauber/apostolic-fathers
  `texts/`, Lake's text as corrected by James Tauber and Seumas Macdonald
  (*Open Apostolic Fathers* 1.0, doi:10.5281/zenodo.2555673), CC BY-SA 4.0.
  **English**: jcuenod/CAFE, the *Contemporary Apostolic Fathers Edition*,
  a machine translation (GPT-4o's first drafts, published without
  systematic human revision), CC BY-SA 4.0. Both pinned in `pins.json` →
  `fathers`.

  Each file is one line per verse, `<reference> <text>`; CAFE translates
  the Greek file line by line, so the two are joined by line and must carry
  the same references in the same order (`join/2` stops the build
  otherwise, naming every difference). One passage per line, in the ancient
  pack's schema (`Bezalel.Data.FathersPack`), the works registered in core's
  `Bezalel.Study.Ancient.Fathers`.

  Rules (the report counts each):

    * the text is the files' own; a line's end is trimmed, nothing else is
      changed;
    * Lake's section titles, `<book>.0.0` in the Shepherd ('Ὅρασις αʹ') and
      `EP.0` in the Martyrdom (the Latin heading of the Moscow epilogue),
      are headings, not text: not imported;
    * the subscriptions `SB.1` (1 Clement and Barnabas, the manuscripts'
      closing titles) are outside the works' numbering: not imported;
    * the Shepherd is three works by book (1–5 Visions, 6–17 Mandates 1–12,
      18–27 Similitudes 1–10); the Martyrdom's `EP.<n>` lines are the Moscow
      epilogue, a work of its own;
    * a passage is Latin when it has no Greek letter;
    * any other reference stops the build.
  """

  alias Bezalel.Data.Net
  alias Bezalel.Study.Ancient
  alias Bezalel.Study.Ancient.Passages

  @license "CC BY-SA 4.0"

  @edition "Kirsopp Lake, The Apostolic Fathers (Loeb Classical Library, 1912–1913), as " <>
             "corrected in Open Apostolic Fathers 1.0, ed. James Tauber and Seumas Macdonald " <>
             "(2019), doi:10.5281/zenodo.2555673"

  @translation "CAFE, Contemporary Apostolic Fathers Edition (James Cuénod, 2024): a machine " <>
                 "translation, GPT-4o's first drafts (gpt-4o-2024-05-13) published without " <>
                 "systematic human revision; not a published human translation"

  # File stem → the work its lines are (the Shepherd and the Martyrdom are
  # split by reference, `classify/2`).
  @files [
    {"001-i_clement", "1_clement"},
    {"002-ii_clement", "2_clement"},
    {"003-ignatius-ephesians", "ignatius_ephesians"},
    {"004-ignatius-magnesians", "ignatius_magnesians"},
    {"005-ignatius-trallians", "ignatius_trallians"},
    {"006-ignatius-romans", "ignatius_romans"},
    {"007-ignatius-philadelphians", "ignatius_philadelphians"},
    {"008-ignatius-smyrnaeans", "ignatius_smyrnaeans"},
    {"009-ignatius-polycarp", "ignatius_polycarp"},
    {"010-polycarp-philippians", "polycarp_philippians"},
    {"011-didache", "didache"},
    {"012-barnabas", "barnabas"},
    {"013-shepherd", :hermas},
    {"014-martyrdom", "martyrdom_of_polycarp"},
    {"015-diognetus", "diognetus"}
  ]

  # The Shepherd's books: {first, last, work}; a work's book n is file book first + n - 1.
  @hermas [{1, 5, "hermas_visions"}, {6, 17, "hermas_mandates"}, {18, 27, "hermas_similitudes"}]

  # The code and data that decide the pack's rows, relative to data/.
  @build_inputs ~w(
    lib/bezalel/data/fathers.ex lib/bezalel/data/fathers_pack.ex
    lib/bezalel/data/scrolls_pack.ex lib/bezalel/data/pack.ex
    lib/mix/tasks/bezalel.data.fathers.ex
    ../lib/bezalel/study/ancient.ex ../lib/bezalel/study/ancient/registry.ex
    ../lib/bezalel/study/ancient/fathers.ex
    ../lib/bezalel/study/ancient/passages.ex ../lib/bezalel/study/patterns.ex
  )

  @doc """
  One checksum of the files that decide the pack's rows (`@build_inputs`),
  recorded in `pack_meta.build_sha256` so a publish can tell a pack built by
  other code.
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

  @doc "The file stems, in Lake's order."
  @spec stems() :: [String.t()]
  def stems, do: Enum.map(@files, &elem(&1, 0))

  @doc "The Greek file name of `stem`."
  @spec greek_file(String.t()) :: String.t()
  def greek_file(stem), do: stem <> ".txt"

  @doc "The English (CAFE) file name of `stem`."
  @spec english_file(String.t()) :: String.t()
  def english_file(stem), do: stem <> ".en.txt"

  @doc """
  The passages' edition, translation, licence and the Greek files' page at
  the pinned commit (`pin` is `pins.json` → `fathers`).
  """
  @spec provenance(map()) :: map()
  def provenance(pin) do
    greek = pin["greek"]
    english = pin["english"]

    %{
      edition: @edition,
      translation: @translation,
      license: @license,
      blob: "#{greek["repo"]}/blob/#{greek["commit"]}/#{greek["path"]}/",
      greek_source: "#{greek["repo"]}/tree/#{greek["commit"]}/#{greek["path"]}",
      english_source: "#{english["repo"]}/tree/#{english["commit"]}"
    }
  end

  @doc """
  A file's lines as `{line number, reference, text}`. Raises on a line that
  isn't `<reference> <text>`.
  """
  @spec parse(String.t(), binary()) :: [{pos_integer(), String.t(), String.t()}]
  def parse(name, bytes) do
    bytes
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _} -> String.trim(line) == "" end)
    |> Enum.map(fn {line, number} ->
      case String.split(String.trim_trailing(line), " ", parts: 2) do
        [reference, text] when reference != "" and text != "" ->
          {number, reference, text}

        _ ->
          raise ArgumentError, "#{name}:#{number}: not '<reference> <text>': #{inspect(line)}"
      end
    end)
  end

  @doc """
  The Greek and English lines of one file joined by line: `{:ok, [{line,
  reference, greek, english}]}`, or `{:error, differences}` naming each
  reference only one side has and each line whose references differ.
  """
  @spec join([{pos_integer(), String.t(), String.t()}], [{pos_integer(), String.t(), String.t()}]) ::
          {:ok, [{pos_integer(), String.t(), String.t(), String.t()}]} | {:error, [String.t()]}
  def join(greek, english) do
    greek_refs = Enum.map(greek, &elem(&1, 1))
    english_refs = Enum.map(english, &elem(&1, 1))

    differences =
      Enum.map(greek_refs -- english_refs, &"#{&1}: Greek only") ++
        Enum.map(english_refs -- greek_refs, &"#{&1}: English only") ++
        for(
          {{gl, g, _}, {el, e, _}} <- Enum.zip(greek, english),
          g != e or gl != el,
          do: "Greek line #{gl} #{g}, English line #{el} #{e}"
        )

    if differences == [],
      do:
        {:ok,
         Enum.zip_with(greek, english, fn {line, ref, g}, {_, _, e} -> {line, ref, g, e} end)},
      else: {:error, differences}
  end

  @doc """
  What a line of `stem` is: `{:passage, work_key, levels}` (the numbers it
  is cited by in that work), `:heading` or `:subscription`. Raises on any
  other reference.
  """
  @spec classify(String.t(), String.t()) ::
          {:passage, String.t(), [non_neg_integer()]} | :heading | :subscription
  def classify(stem, reference) do
    {_, work} = List.keyfind(@files, stem, 0) || raise(ArgumentError, "unknown file #{stem}")
    parts = String.split(reference, ".")

    case {work, parts} do
      {_, ["SB", _]} ->
        :subscription

      {"martyrdom_of_polycarp", ["EP", "0"]} ->
        :heading

      {"martyrdom_of_polycarp", ["EP", n]} ->
        {:passage, "martyrdom_of_polycarp_moscow_epilogue", [number!(stem, reference, n)]}

      {:hermas, [_book, "0", "0"]} ->
        :heading

      {:hermas, [book, chapter, verse]} ->
        hermas(stem, reference, Enum.map([book, chapter, verse], &number!(stem, reference, &1)))

      {key, [chapter, verse]} when is_binary(key) ->
        {:passage, key, Enum.map([chapter, verse], &number!(stem, reference, &1))}

      _ ->
        raise ArgumentError, "#{stem}: unknown reference #{inspect(reference)}"
    end
  end

  defp hermas(stem, reference, [book | rest]) do
    case Enum.find(@hermas, fn {first, last, _} -> book in first..last end) do
      {first, _, key} -> {:passage, key, [book - first + 1 | rest]}
      nil -> raise ArgumentError, "#{stem}: book #{book} of #{reference} isn't the Shepherd's"
    end
  end

  defp number!(stem, reference, text) do
    case Integer.parse(text) do
      {n, ""} when n >= 0 -> n
      _ -> raise ArgumentError, "#{stem}: unknown reference #{inspect(reference)}"
    end
  end

  @doc """
  The pack's passages from `files` (stem → `{greek bytes, english bytes}`)
  and the report's counts: `{rows, %{headings: [...], subscriptions: [...],
  latin: n, per_work: %{key => n}}}`. Raises if a file's Greek and English
  references differ (`join/2`).
  """
  @spec passages(%{String.t() => {binary(), binary()}}, map()) :: {[map()], map()}
  def passages(files, provenance) do
    corpus = Ancient.corpus("apostolic_fathers")

    {rows, skipped} =
      Enum.flat_map_reduce(stems(), %{headings: [], subscriptions: []}, fn stem, skipped ->
        {greek, english} = Map.fetch!(files, stem)
        greek = parse(greek_file(stem), greek)
        english = parse(english_file(stem), english)

        lines =
          case join(greek, english) do
            {:ok, lines} ->
              lines

            {:error, differences} ->
              raise ArgumentError,
                    "#{stem}: Greek and English differ:\n" <> Enum.join(differences, "\n")
          end

        Enum.flat_map_reduce(lines, skipped, &line(&1, &2, stem, corpus, provenance))
      end)

    {rows,
     %{
       headings: Enum.reverse(skipped.headings),
       subscriptions: Enum.reverse(skipped.subscriptions),
       latin: Enum.count(rows, &(&1.original_language == "Latin")),
       per_work: Enum.frequencies_by(rows, & &1.work_key)
     }}
  end

  defp line({number, reference, greek, english}, skipped, stem, corpus, provenance) do
    case classify(stem, reference) do
      :heading ->
        {[], %{skipped | headings: [{stem, reference, greek} | skipped.headings]}}

      :subscription ->
        {[], %{skipped | subscriptions: [{stem, reference, greek} | skipped.subscriptions]}}

      {:passage, key, levels} ->
        work = Ancient.work(corpus, key) || raise ArgumentError, "#{key} isn't registered"
        {[row(work, levels, number, greek, english, stem, provenance)], skipped}
    end
  end

  defp row(work, levels, number, greek, english, stem, provenance) do
    locator = Enum.join(levels, ".")
    key = Enum.reduce(levels, 0, &(&2 * work.locator.scale + &1))

    if length(levels) != work.locator.depth,
      do: raise(ArgumentError, "#{work.key} #{locator}: not #{work.locator.name}")

    %{
      corpus: "apostolic_fathers",
      author: work.author,
      work_key: work.key,
      work_title: work.title,
      reference: "#{Ancient.display_title(work)} #{locator}",
      alternate_reference: nil,
      book_number: hd(levels),
      section_number: levels |> tl() |> Enum.join("."),
      section_end: List.last(levels),
      editorial_heading: nil,
      text: english,
      original_text: greek,
      period_tags: Enum.join(Ancient.corpus("apostolic_fathers").periods, ","),
      edition: provenance.edition,
      translation: provenance.translation,
      license: provenance.license,
      source_url: "#{provenance.blob}#{greek_file(stem)}#L#{number}",
      collection: nil,
      sort_start: key,
      sort_end: key,
      original_language: language(greek),
      original_license: provenance.license,
      translation_license: provenance.license
    }
  end

  @doc "Greek, or Latin when the text has no Greek letter."
  @spec language(String.t()) :: String.t()
  def language(text) do
    if Regex.match?(Regex.compile!("[\\x{0370}-\\x{03FF}\\x{1F00}-\\x{1FFF}]", "u"), text),
      do: "Greek",
      else: "Latin"
  end

  @doc """
  The search text of a passage's original: editorial signs dropped, marks
  and case folded by core's `Bezalel.Study.Ancient.Passages`, which folds
  the queries; the ancient pack's Greek (Josephus, Philo) folds the same.
  """
  @spec index_text(String.t()) :: String.t()
  def index_text(original), do: original |> Passages.strip_editorial_signs() |> Passages.fold()

  @doc """
  One digest of every pinned file's sha256, Greek and English (`pin` is
  `pins.json` → `fathers`), recorded as `pack_meta.fathers_sha256`.
  """
  @spec digest(map()) :: String.t()
  def digest(pin) do
    Net.digest(Enum.sort(pin["greek"]["files"]) ++ Enum.sort(pin["english"]["files"]))
  end

  @doc """
  The report text (`out/fathers_report.txt`): the sources, the passages per
  work, the Latin ones, and every line left out, with its rule.
  """
  @spec report(map()) :: String.t()
  def report(%{source: source, rows: rows, counts: counts}) do
    per_work =
      for work <- Ancient.corpus("apostolic_fathers").works,
          do: "  #{work.key}: #{Map.get(counts.per_work, work.key, 0)} (#{work.title})"

    skipped = fn list ->
      for {stem, reference, text} <- list, do: "  #{stem} #{reference}: #{text}"
    end

    Enum.join(
      [
        "The fathers pack (mix bezalel.data.fathers)",
        "",
        source,
        "",
        "Greek and English: every reference of every file on both sides, in the same order, " <>
          "line for line (join/2; the build stops otherwise).",
        "",
        "#{length(rows)} passages (#{counts.latin} Latin), by work:"
      ] ++
        per_work ++
        ["", "Left out, Lake's section titles (headings, not text): #{length(counts.headings)}"] ++
        skipped.(counts.headings) ++
        [
          "",
          "Left out, subscriptions (the manuscripts' closing titles, outside the numbering): " <>
            "#{length(counts.subscriptions)}"
        ] ++ skipped.(counts.subscriptions) ++ [""],
      "\n"
    )
  end
end
