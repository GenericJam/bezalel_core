defmodule Bezalel.Data.FathersPack do
  @moduledoc """
  Writes the `fathers` pack (`Bezalel.Data.Pack.build/5`): the Apostolic
  Fathers' passages in the ancient pack's own tables and schema
  (`Bezalel.Data.ScrollsPack.ancient_schema/0`: `ancient_source_passages`,
  its FTS5 index `ancient_source_passages_fts` with the same columns and
  tokenizer, and the empty `ancient_source_biblical_links` and
  `ancient_source_notes`), so the ancient-source tools read it with the same
  SQL.
  """

  alias Bezalel.Data.{Fathers, Pack, ScrollsPack}

  @pack %{
    name: "fathers",
    description:
      "The Apostolic Fathers: Lake's Greek (and Latin) as corrected by Tauber and Macdonald, " <>
        "with CAFE's machine-translated English",
    tables: ~w(ancient_source_passages ancient_source_passages_fts
               ancient_source_biblical_links ancient_source_notes)
  }

  @fts_columns ~w(passage_id work_title reference text original_text_folded original_prefix_variants)a

  @doc "The pack's name, description and tables."
  @spec pack() :: map()
  def pack, do: @pack

  @doc """
  Writes `path` with `passages` (`Bezalel.Data.Fathers.passages/2` rows,
  given ids 1, 2, … in order, each indexed for search) and `meta`.
  """
  @spec write(Path.t(), [map()], %{String.t() => String.t()}) :: :ok
  def write(path, passages, meta) do
    passages =
      passages |> Enum.with_index(1) |> Enum.map(fn {row, id} -> Map.put(row, :id, id) end)

    columns = ScrollsPack.passage_columns()

    Pack.build(path, @pack, ScrollsPack.ancient_schema(), meta, fn conn ->
      Pack.insert!(conn, "ancient_source_passages", columns, passages, fn row ->
        Enum.map(columns, &Map.fetch!(row, &1))
      end)

      Pack.insert!(conn, "ancient_source_passages_fts", @fts_columns, passages, &fts_values/1)

      Pack.exec!(
        conn,
        "INSERT INTO ancient_source_passages_fts(ancient_source_passages_fts) VALUES('optimize')"
      )
    end)
  end

  @doc "A passage's search-index row: its English and its folded original (no Hebrew prefixes)."
  @spec fts_values(map()) :: list()
  def fts_values(row) do
    [
      row.id,
      row.work_title,
      row.reference,
      row.text,
      Fathers.index_text(row.original_text || ""),
      ""
    ]
  end
end
