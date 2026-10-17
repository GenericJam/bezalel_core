defmodule Bezalel.Study.Tools.GetStudyNotes do
  @moduledoc """
  `get_study_notes`: the Tyndale study notes and the unfoldingWord and SIL
  translator notes on a verse or chapter (the notes pack's BibleAquifer
  content).

  Ported from studybible-mcp's `handle_get_study_notes`, `get_study_notes`,
  `get_chapter_study_notes`, `_to_aquifer_ref` and `format_study_notes`
  (MIT). Same text. A verse's notes are those on the verse and the ranges
  covering it; a chapter's are those starting in it. A reference naming no
  verse or chapter of the 66 books ("not a reference", "Tobit 1") is an
  error with their "No study notes found" text; the pack's own absence is
  the pack error, in place of their "Aquifer data not available" message.
  `result/1` returns the notes untruncated.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format, Reference}
  require Args

  @books ~w(Gen Exo Lev Num Deu Jos Jdg Rut 1Sa 2Sa 1Ki 2Ki 1Ch 2Ch Ezr Neh Est Job Psa Pro
            Ecc Sng Isa Jer Lam Ezk Dan Hos Jol Amo Oba Jon Mic Nam Hab Zep Hag Zec Mal
            Mat Mrk Luk Jhn Act Rom 1Co 2Co Gal Eph Php Col 1Th 2Th 1Ti 2Ti Tit Phm Heb Jas
            1Pe 2Pe 1Jn 2Jn 3Jn Jud Rev)
  # Aquifer numbers the books 01-66 in this order.
  @book_numbers @books
                |> Enum.with_index(1)
                |> Map.new(fn {book, n} -> {book, String.pad_leading("#{n}", 2, "0")} end)

  @labels %{
    "study_notes" => "Tyndale Study Notes",
    "translation_notes_uw" => "Translation Notes (unfoldingWord)",
    "translation_notes_sil" => "Translation Notes (SIL)"
  }

  @impl true
  def name, do: "get_study_notes"

  @impl true
  def description do
    """
    Get scholarly study notes and translation notes for a Bible verse or chapter.

    Returns combined commentary from:
    - **Tyndale Study Notes**: Concise, verse-level scholarly commentary (66 books)
    - **UW Translation Notes**: Translator-focused commentary with linguistic insights
    - **SIL Translator Notes**: Additional translation and cultural context

    Relevant for published commentary on a specific verse, difficult passages,
    translation and cultural background, and chapter-level overviews of themes and
    context. The content is published scholarship, quoted as-is with source
    attribution. For journal articles, see `list_research_sources`.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "reference" => %{
          "type" => "string",
          "description" => "Bible reference (e.g., 'John 3:16', 'Genesis 1', 'Romans 8:28')"
        },
        "chapter_only" => %{
          "type" => "boolean",
          "description" =>
            "If true, return all notes for the chapter. Default: false (verse-specific)"
        }
      },
      "required" => ["reference"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc """
  A note: its source (`resource_type`: study_notes, translation_notes_uw or
  translation_notes_sil), heading and text, and the Aquifer references
  ('43003016', book, chapter and verse numbers) it spans.
  """
  @type note :: %{
          resource_type: String.t(),
          title: String.t(),
          content: String.t(),
          start_ref: String.t() | nil,
          end_ref: String.t() | nil
        }

  @type t :: %{reference: String.t(), notes: [note()]}

  @doc """
  The notes on `args`' verse, or on its chapter with `chapter_only` or a
  chapter reference (possibly none). No reference, or one naming no verse
  or chapter of the 66 books, is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    reference = Args.reference(args)
    chapter_only = Args.flag(args, "chapter_only", false)

    query =
      cond do
        reference == "" ->
          :none

        chapter_only or not String.contains?(reference, ":") ->
          chapter_query(reference, chapter_only)

        true ->
          verse_query(reference)
      end

    case query do
      :none ->
        {:error, "Please provide a Bible reference (e.g., 'John 3:16' or 'Genesis 1')."}

      nil ->
        {:error, "No study notes found for #{reference}."}

      {sql, params} ->
        with {:ok, rows} <- DB.with_pack(:notes, &DB.all(&1, sql, params)) do
          {:ok, %{reference: reference, notes: Enum.map(rows, &note/1)}}
        end
    end
  end

  @columns "resource_type, title, content_plain, start_ref, end_ref"
  @types "resource_type IN ('study_notes', 'translation_notes_uw', 'translation_notes_sil')"

  # With chapter_only, the chapter of any reference ('John 3:16' is John 3);
  # otherwise a whole-chapter reference, else the reference as a verse.
  defp chapter_query(reference, chapter_only) do
    chapter =
      case chapter_only && Reference.parse_passage(reference) do
        %{book: book, start_chapter: chapter} -> {book, chapter}
        _ -> Reference.single_chapter(reference)
      end

    case chapter do
      {book, number} when is_map_key(@book_numbers, book) and Args.is_sqlite_integer(number) ->
        {"""
         SELECT #{@columns} FROM aquifer_content
         WHERE #{@types} AND book = ? AND chapter_start = ?
         ORDER BY resource_type, start_ref
         """, [book, number]}

      {_book, _number} ->
        nil

      nil ->
        verse_query(reference)
    end
  end

  defp verse_query(reference) do
    if aquifer = aquifer_ref(Reference.normalize(reference)) do
      {"""
       SELECT #{@columns} FROM aquifer_content
       WHERE #{@types}
         AND (start_ref = ? OR (start_ref <= ? AND end_ref >= ? AND is_range = 1))
       ORDER BY resource_type, start_ref
       """, [aquifer, aquifer, aquifer]}
    end
  end

  # 'Jhn.3.16' as Aquifer's '43003016'; nil for anything else.
  defp aquifer_ref(normalized) do
    with [book, chapter, verse] <- String.split(normalized, "."),
         {:ok, number} <- Map.fetch(@book_numbers, book),
         {chapter, ""} <- Integer.parse(chapter),
         {verse, ""} <- Integer.parse(verse) do
      number <> pad(chapter) <> pad(verse)
    else
      _ -> nil
    end
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(3, "0")

  defp note(row) do
    %{
      resource_type: row["resource_type"],
      title: row["title"],
      content: row["content_plain"],
      start_ref: row["start_ref"],
      end_ref: row["end_ref"]
    }
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{reference: reference, notes: []}), do: "No study notes found for #{reference}."

  def render(%{reference: reference, notes: notes}) do
    groups =
      notes
      |> Enum.chunk_by(& &1.resource_type)
      |> Enum.flat_map(fn [%{resource_type: type} | _] = group ->
        ["### #{Map.get(@labels, type, type)}", ""] ++ Enum.flat_map(group, &note_lines/1)
      end)

    "## Study Notes: #{reference}\n\n" <> Enum.join(groups, "\n")
  end

  defp note_lines(note) do
    title = if Format.present?(note.title), do: ["**#{note.title}**"], else: []

    content =
      if Format.present?(note.content),
        do: [Format.truncate(note.content, 2000, "\n\n*[Note truncated]*")],
        else: []

    title ++ content ++ [""]
  end
end
