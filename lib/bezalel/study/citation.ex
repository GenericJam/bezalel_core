defmodule Bezalel.Study.Citation do
  @moduledoc """
  One source a study tool's result rests on: a record of a work (a verse,
  a lexicon entry, a note, an ancient passage, a manuscript, a book), with
  where to read it. `Bezalel.Study.Citations` builds them, one function per
  work; a tool returns them with its Markdown as `details.citations`, and
  writes `source_line/1` under each record so the model can copy the link.

    * `work`: the work's key ("net", "bdb", "josephus", "dss", "theology:stott"…;
      `Bezalel.Study.Citations.work_title/1` names it).
    * `label`: what a sources list shows ("John 3:16", "BDB H430 אֱלֹהִים").
    * `url`: the reader page for this record, or nil for a print-only book.
    * `locator`: the place in the work ("John 3:16", "H430", "Ant. 18.63",
      "4Q37 12:13–14", "pp. 52-55").
    * `book`: for a book citation, `%{author, title, year}` and optionally
      `publisher`, `edition`, `pages` (atom keys, as `from_map/1` restores them); nil otherwise.
    * `licence`: the record's licence when it asks for credit with each use
      (CC BY-NC), else nil (the credits page has the rest).
    * `dataset_url`: the pinned file Bezalel imported the record from.
    * `translation`: `:published` (the tool's English is a published
      translation, or there is no English to speak of), `:assistant` (the
      tool gives the original only, or English of something else, as the
      Targum's: any English for it is the model's own, an AI translation)
      or `:unpublished_draft` (an unpublished, AI-assisted rendering the
      tool quotes, the "HLT").
    * `original`: for `:assistant` and `:unpublished_draft`, the
      original-language texts to check it against, `[%{label, url}]`.
    * `cited`: set by `Bezalel.Study.Citations.mark/2`: the reply links it
      (or names the book).

  `to_map/1` and `from_map/1` convert to and from the JSON-safe map a
  session stores (`Bezalel.Agent.keep_details/2`).
  """

  @enforce_keys [:work, :label]
  defstruct [
    :work,
    :label,
    :url,
    :locator,
    :book,
    :licence,
    :dataset_url,
    translation: :published,
    original: [],
    cited: false
  ]

  @type translation :: :published | :assistant | :unpublished_draft

  @type t :: %__MODULE__{
          work: String.t(),
          label: String.t(),
          url: String.t() | nil,
          locator: String.t() | nil,
          book: map() | nil,
          licence: String.t() | nil,
          dataset_url: String.t() | nil,
          translation: translation(),
          original: [%{label: String.t(), url: String.t()}],
          cited: boolean()
        }

  @translations %{
    "published" => :published,
    "assistant" => :assistant,
    "unpublished_draft" => :unpublished_draft
  }

  @doc """
  The citation as Markdown for the model to copy: `[label](url)`, or the
  book (`Author, *Title* (year), locator`), with what an AI translation or
  an unpublished draft must say.
  """
  @spec markdown(t()) :: String.t()
  def markdown(%__MODULE__{translation: :unpublished_draft} = c) do
    "unpublished draft rendering (AI-assisted), not Heiser's#{originals(c, "; original: ")}"
  end

  def markdown(%__MODULE__{translation: :assistant} = c) do
    link(c) <>
      " (original text: any English you give for it is your own translation; say so and link this)"
  end

  def markdown(%__MODULE__{} = c), do: link(c)

  @doc """
  The `Source:` line under a record: one citation, or several joined with
  " · ". Empty for none.
  """
  @spec source_line(t() | [t()]) :: String.t()
  def source_line([]), do: ""
  def source_line(%__MODULE__{} = c), do: source_line([c])
  def source_line(citations), do: "Source: " <> Enum.map_join(citations, " · ", &markdown/1)

  @doc "The citation's link (`[label](url)`), or its book reference when it has no URL."
  @spec link(t()) :: String.t()
  def link(%__MODULE__{url: url, label: label}) when is_binary(url),
    do: "[#{escape(label)}](#{url})"

  def link(%__MODULE__{book: %{} = book} = c), do: book_text(book, c.locator)
  def link(%__MODULE__{label: label}), do: label

  @doc """
  A book as a reference: `Author, *Title* (Publisher, year), locator`;
  the parts it has.
  """
  @spec book_text(map(), String.t() | nil) :: String.t()
  def book_text(book, locator \\ nil) do
    imprint =
      [book[:edition], book[:publisher], book[:year]]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map_join(", ", &to_string/1)

    [
      book[:author],
      "*#{book[:title]}*" <> if(imprint == "", do: "", else: " (#{imprint})"),
      locator || book[:pages]
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  @doc """
  The dedup key: its URL and locator (two passages on one manuscript's page
  stay two), else its work and locator (or label).
  """
  @spec key(t()) :: term()
  def key(%__MODULE__{url: url} = c) when is_binary(url), do: {url, c.locator}
  def key(%__MODULE__{} = c), do: {c.work, c.locator || c.label}

  @doc "A JSON-safe map with string keys, as a session stores it."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = c) do
    %{
      "work" => c.work,
      "label" => c.label,
      "url" => c.url,
      "locator" => c.locator,
      "book" => c.book && Map.new(c.book, fn {k, v} -> {to_string(k), v} end),
      "licence" => c.licence,
      "dataset_url" => c.dataset_url,
      "translation" => Atom.to_string(c.translation),
      "original" => Enum.map(c.original, &%{"label" => &1.label, "url" => &1.url})
    }
    |> Map.reject(fn {_k, v} -> v in [nil, []] end)
  end

  @doc "A citation back from `to_map/1`'s map (nil for anything else)."
  @spec from_map(term()) :: t() | nil
  def from_map(%__MODULE__{} = c), do: c

  def from_map(%{"work" => work, "label" => label} = m)
      when is_binary(work) and is_binary(label) do
    %__MODULE__{
      work: work,
      label: label,
      url: m["url"],
      locator: m["locator"],
      book: book(m["book"]),
      licence: m["licence"],
      dataset_url: m["dataset_url"],
      translation: Map.get(@translations, m["translation"], :published),
      original: for(%{"label" => l, "url" => u} <- m["original"] || [], do: %{label: l, url: u})
    }
  end

  def from_map(_other), do: nil

  @book_fields %{
    "author" => :author,
    "title" => :title,
    "year" => :year,
    "publisher" => :publisher,
    "edition" => :edition,
    "pages" => :pages
  }

  defp book(%{} = stored),
    do: for({k, v} <- stored, field = @book_fields[k], into: %{}, do: {field, v})

  defp book(_none), do: nil

  defp originals(%__MODULE__{original: []}, _prefix), do: ""

  defp originals(%__MODULE__{original: original}, prefix),
    do: prefix <> Enum.map_join(original, ", ", &"[#{escape(&1.label)}](#{&1.url})")

  # Square brackets in a label would end the link text early.
  defp escape(label), do: String.replace(label, ["[", "]"], fn c -> "\\" <> c end)
end
