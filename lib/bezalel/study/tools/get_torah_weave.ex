defmodule Bezalel.Study.Tools.GetTorahWeave do
  @moduledoc """
  `get_torah_weave`: the cells a Torah verse is paired with under Moshe
  Kline's Woven Torah hypothesis (the core pack's `torah_weave_*` tables).

  Ported from studybible-mcp's `handle_get_torah_weave`,
  `get_torah_weave_cells_for_reference`, `get_torah_weave_unit_cells`,
  `compute_torah_weave_partners` and `format_torah_weave` (MIT). Same text.
  A reference that isn't a verse of Genesis–Deuteronomy ("Matthew 5:1",
  "Genesis") is an error with their "No Torah Weave unit contains …" text;
  a Torah verse no cell covers is that text as a result. Their "Torah Weave
  data not available" message is gone: the tables are in the core pack, so
  a missing pack is the pack error.

  `result/1` returns each matching cell with its unit and its partner
  cells by direction.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Reference}

  @torah ~w(Gen Exo Lev Num Deu)

  @type_labels %{
    "F" => "Framework (marks structural boundaries)",
    "CL" => "Closure (provides envelope closure)",
    "U" => "Unique (stands outside triadic groupings)"
  }

  @directional_doc """
  ### How to read Torah Weave partners

  Under Moshe Kline's Woven Torah hypothesis, each Torah unit is a 2D grid whose \
  cells are deliberately paired in two directions:

  - **Horizontal partners** (same row, different column) are **parallel correspondences** \
  at the same compositional tier. Rows in Kline's method carry divine-name registers \
  (Row 1 tends to feature YHWH as active subject, Row 3 Elohim, Row 2 the interface \
  between them), so horizontal partners sit at the same register but on different \
  thematic tracks. Read them as a symmetry: the two cells are the same "note" played \
  in different thematic keys. Look for inversion, contrast, completion, or framework-\
  and-filling.

  - **Vertical partners** (same column, different row) are **progressions through \
  divine-name registers along a single thematic track**. Columns are thematic tracks, \
  so vertical partners follow one theme as it moves through the register hierarchy. \
  Read them as development, not symmetry. Look for escalation, register shift, or \
  narrative arc.

  - **Sibling cells** (same row + column, adjacent subdivisions) are an internal \
  progression inside a single cell position. Read them sequentially.

  The text of the partner cells is not included above; `lookup_verse` returns it for \
  each verse range. The thematic content of each unit's columns is not labelled in \
  Kline's dataset; under his method it is inferred from the verses themselves.\
  """

  @impl true
  def name, do: "get_torah_weave"

  @impl true
  def description do
    """
    Get the structurally-paired verses for a Torah passage under Moshe Kline's Woven Torah hypothesis.

    The Torah is organised as 86 two-dimensional literary units (Genesis–Deuteronomy). Each unit is a grid of cells arranged in rows and columns, and cells are deliberately paired with one another across rows (horizontal partners) and down columns (vertical partners). A verse's weave partners are therefore the passages the hypothesis holds the Torah's author(s) intended to be read alongside it.

    Relevant to any passage in Genesis, Exodus, Leviticus, Numbers, or Deuteronomy —
    particularly for identifying which verses are structurally paired with a
    passage, for suspected deliberate interweaving (doublets, creation/flood, law
    parallels), and for comparative readings where the pairing claimed is
    compositional rather than thematic.

    WHAT IT RETURNS:
    - The literary unit the verse sits in (title, format, type, verse span)
    - The cell the verse occupies (row/column label + verse range)
    - Horizontal partner cells (same row, same subdivision, different column)
    - Vertical partner cells (same column, same subdivision, different row)
    - Sibling cells (same row and column, adjacent subdivisions)
    - A short explanation of what each direction of pairing means under Kline's method

    The output is a set of structural pointers — verse ranges and their pairing
    direction — not pre-written interpretation. The text of the partner cells is
    not included; `lookup_verse` returns it. Under Kline's method horizontal
    partners are symmetric parallels (same divine-name register, different thematic
    tracks) and vertical partners are a progression through registers along a single
    thematic track; the thematic content of each column is not labelled in Kline's
    dataset.

    Only Torah books (Genesis through Deuteronomy) have weave data. Source: Moshe Kline, chaver.com, CC BY 4.0.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "reference" => %{
          "type" => "string",
          "description" =>
            "Bible reference in Genesis–Deuteronomy (e.g., 'Genesis 6:1', 'Exodus 14:21', 'Leviticus 19:18')"
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
  A weave cell: its label ('2Bc'), row, column, subdivision (nil for a
  whole cell) and verse span, `reference` as the tool prints it.
  """
  @type cell :: %{
          id: integer(),
          label: String.t(),
          row: integer(),
          column: String.t(),
          subdivision: String.t() | nil,
          chapter_start: integer(),
          verse_start: integer(),
          chapter_end: integer(),
          verse_end: integer(),
          reference: String.t()
        }

  @typedoc "A unit of the weave: `type` is 'F', 'CL', 'U' or nil."
  @type unit :: %{
          id: integer(),
          number: integer(),
          book: String.t(),
          title: String.t(),
          verses: String.t(),
          format: String.t(),
          irregular: boolean(),
          unique: boolean(),
          type: String.t() | nil
        }

  @typedoc "A cell containing the verse, with its unit and partners."
  @type match :: %{
          unit: unit(),
          cell: cell(),
          horizontal: [cell()],
          vertical: [cell()],
          siblings: [cell()]
        }

  @type t :: %{reference: String.t(), matches: [match()]}

  @doc """
  The weave cells containing `args`' verse with their partners (none when
  no cell covers a Torah verse); a reference that isn't a verse of
  Genesis–Deuteronomy is an error.
  """
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    reference = Args.reference(args)

    cond do
      reference == "" ->
        {:error, "Please provide a Bible reference in Genesis–Deuteronomy."}

      verse = torah_verse(reference) ->
        lookup(reference, verse)

      true ->
        {:error, render(%{reference: reference, matches: []})}
    end
  end

  defp lookup(reference, {book, chapter, verse}) do
    with {:ok, matches} <- DB.with_pack(:core, &matches(&1, book, chapter * 1000 + verse)) do
      {:ok, %{reference: reference, matches: matches}}
    end
  end

  defp torah_verse(reference) do
    with [book, chapter, verse | _] when book in @torah <-
           reference |> Reference.normalize() |> String.split("."),
         {chapter, ""} <- Integer.parse(chapter),
         {verse, ""} <- Integer.parse(verse) do
      {book, chapter, verse}
    else
      _ -> nil
    end
  end

  defp matches(conn, book, target) do
    found =
      DB.all(
        conn,
        """
        SELECT c.*,
               u.unit_number AS unit_number,
               u.book_full AS unit_book_full,
               u.title AS unit_title,
               u.verses AS unit_verses,
               u.format AS unit_format,
               u.irregular AS unit_irregular,
               u.is_unique AS unit_is_unique,
               u.type AS unit_type
        FROM torah_weave_cells c
        JOIN torah_weave_units u ON u.id = c.unit_id
        WHERE c.book = ?
          AND c.sort_start <= ?
          AND c.sort_end >= ?
        ORDER BY (c.sort_end - c.sort_start) ASC, c.row_num, c.column_letter
        """,
        [book, target, target]
      )

    unit_cells =
      found
      |> Enum.map(& &1["unit_id"])
      |> Enum.uniq()
      |> Map.new(fn unit_id ->
        {unit_id,
         DB.all(
           conn,
           """
           SELECT * FROM torah_weave_cells
           WHERE unit_id = ?
           ORDER BY row_num, column_letter,
                    CASE WHEN subdivision IS NULL THEN '' ELSE subdivision END
           """,
           [unit_id]
         )}
      end)

    Enum.map(found, &match(&1, Map.fetch!(unit_cells, &1["unit_id"])))
  end

  defp match(row, unit_cells) do
    book_full = row["unit_book_full"]
    cell = cell(row, book_full)
    others = for c <- unit_cells, c["id"] != row["id"], do: cell(c, book_full)

    %{
      unit: %{
        id: row["unit_id"],
        number: row["unit_number"],
        book: book_full,
        title: row["unit_title"],
        verses: row["unit_verses"],
        format: row["unit_format"],
        irregular: row["unit_irregular"] not in [nil, 0],
        unique: row["unit_is_unique"] not in [nil, 0],
        type: row["unit_type"]
      },
      cell: cell,
      horizontal:
        partners(
          others,
          &(&1.row == cell.row and same_sub(&1, cell) and &1.column != cell.column)
        ),
      vertical:
        partners(
          others,
          &(&1.column == cell.column and same_sub(&1, cell) and &1.row != cell.row)
        ),
      siblings:
        partners(
          others,
          &(&1.row == cell.row and &1.column == cell.column and not same_sub(&1, cell))
        )
    }
  end

  # A cell is horizontal, vertical or sibling, in that order of precedence.
  defp partners(cells, keep) do
    cells |> Enum.filter(keep) |> Enum.sort_by(&{&1.row, &1.column, &1.subdivision || ""})
  end

  defp same_sub(a, b), do: a.subdivision == b.subdivision

  defp cell(row, book_full) do
    %{
      id: row["id"],
      label: row["cell_label"],
      row: row["row_num"],
      column: row["column_letter"],
      subdivision: if(row["subdivision"] in [nil, ""], do: nil, else: row["subdivision"]),
      chapter_start: row["chapter_start"],
      verse_start: row["verse_start"],
      chapter_end: row["chapter_end"],
      verse_end: row["verse_end"],
      reference: cell_reference(row, book_full)
    }
  end

  defp cell_reference(
         %{"chapter_start" => c, "verse_start" => v, "chapter_end" => c, "verse_end" => v},
         book
       ),
       do: "#{book} #{c}:#{v}"

  defp cell_reference(
         %{"chapter_start" => c, "verse_start" => v1, "chapter_end" => c, "verse_end" => v2},
         book
       ),
       do: "#{book} #{c}:#{v1}-#{v2}"

  defp cell_reference(row, book),
    do:
      "#{book} #{row["chapter_start"]}:#{row["verse_start"]}-#{row["chapter_end"]}:#{row["verse_end"]}"

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{reference: reference, matches: []}) do
    "No Torah Weave unit contains #{reference}. Torah Weave data covers Genesis–Deuteronomy only."
  end

  def render(%{reference: reference, matches: matches}) do
    body =
      matches
      |> Enum.map(&match_lines/1)
      |> Enum.intersperse(["\n---\n"])
      |> Enum.concat()

    Enum.join(
      [
        "## Torah Weave for #{reference}\n",
        "*Source: Moshe Kline, Woven Torah hypothesis (chaver.com, CC BY 4.0)*\n"
      ] ++ body ++ ["\n---\n", @directional_doc, ""],
      "\n"
    )
  end

  defp match_lines(%{unit: unit, cell: cell} = match) do
    label = unit.type && @type_labels[unit.type]

    meta =
      ["**Format**: #{unit.format}"] ++
        if(unit.irregular, do: ["irregular"], else: []) ++
        if(unit.unique, do: ["unique (outside triadic pattern)"], else: []) ++
        if(label, do: ["**Type**: #{unit.type} — #{label}"], else: [])

    [
      "### Unit #{unit.id} · \"#{unit.title}\" (#{unit.verses})",
      "",
      Enum.join(meta, " · "),
      "",
      "**Cell position**: `#{cell.label}` — row #{cell.row}, column #{cell.column}#{sub_note(cell)}",
      "**Cell verse range**: #{cell.reference}",
      ""
    ] ++
      direction(
        match.horizontal,
        "#### ⇄ Horizontal weave partners (same row)",
        "*Parallel correspondences at the same compositional tier / divine-name register.*",
        ["#### ⇄ Horizontal weave partners", "*(none — this cell has no row partner)*\n"]
      ) ++
      direction(
        match.vertical,
        "#### ↕ Vertical weave partners (same column)",
        "*Progression through divine-name registers along a single thematic track.*",
        ["#### ↕ Vertical weave partners", "*(none — this cell has no column partner)*\n"]
      ) ++
      direction(
        match.siblings,
        "#### ↔ Sibling cells (same row + column)",
        "*Internal progression within this cell position; read sequentially.*",
        []
      )
  end

  defp direction([], _heading, _gloss, none), do: none

  defp direction(cells, heading, gloss, _none) do
    [heading, gloss] ++
      Enum.map(cells, &"- **Cell #{&1.label}**#{sub_note(&1)} — #{&1.reference}") ++ [""]
  end

  defp sub_note(%{subdivision: nil}), do: ""
  defp sub_note(%{subdivision: sub}), do: " (subdivision #{sub})"
end
