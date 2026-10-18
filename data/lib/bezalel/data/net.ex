defmodule Bezalel.Data.Net do
  @moduledoc """
  The NET Bible's verse text from its publisher's web service, the NET Bible
  API at labs.bible.org (Biblical Studies Press), as `translation_verses`
  rows.

  One request per book (`url/1`) returns every verse with the publisher's
  markup (`formatting=full`). From it:

  - the words are kept as given, with the markup removed; text in small
    capitals (`<span class="smcaps">`, the divine name LORD for YHWH) is
    written in capitals, as print editions read;
  - a Psalm superscription (`<p class="psasuper">`, which the API returns at
    the start of verse 1) becomes verse 0 of its chapter, the study packs'
    convention (`Psa.3.0`);
  - headings are dropped: section titles (`paragraphtitle`), the Hebrew
    letters heading the stanzas of acrostic poems (`lamhebrew`, Psalm 119 and
    Lamentations 1–4) and the speaker labels of the Song of Songs
    (`sosspeaker`);
  - note markers (`<n id="1" />`) are dropped. The NET's translators' and
    study notes are not licensed for this use, and the API's `formatting=full`
    carries only the markers, not the notes;
  - Strong's tags (`<st data-num="…">`) are dropped, keeping their words;
  - a paragraph or line break becomes a space, then runs of whitespace
    collapse to one space.

  Anything else (an unknown element or paragraph class, a superscription
  outside a Psalm's first verse, an unclosed element) raises, so a changed
  service stops the build instead of slipping text in or out.
  """

  alias Bezalel.Data.Books

  @api "https://labs.bible.org/api/"

  @copyright "Scripture quoted by permission. Quotations designated (NET) are from the " <>
               "NET Bible® copyright ©1996, 2019 by Biblical Studies Press, L.L.C. " <>
               "http://netbible.com All rights reserved."

  @text_paragraphs ~w(poetry bodytext otpoetry poetrybreak bodyblock quote)
  @heading_paragraphs ~w(paragraphtitle lamhebrew sosspeaker)
  @inline ~w(st i b sup span)

  @type row :: %{
          reference: String.t(),
          book: String.t(),
          chapter: pos_integer(),
          verse: non_neg_integer(),
          text: String.t()
        }

  @doc "The NET's `translations` row (without the source columns)."
  @spec translation() :: map()
  def translation do
    %{
      key: "net",
      name: "NET Bible",
      abbreviation: "NET",
      url: "http://netbible.org",
      copyright: @copyright,
      licence: "Free non-commercial use by permission (netbible.com/copyright)"
    }
  end

  @doc """
  The API request for a whole book.

      iex> Bezalel.Data.Net.url({"Rut", "Ruth", 4})
      "https://labs.bible.org/api/?passage=Ruth+1-4&type=json&formatting=full"
  """
  @spec url({String.t(), String.t(), pos_integer()}) :: String.t()
  def url({_code, name, chapters}) do
    @api <>
      "?" <>
      URI.encode_query(passage: "#{name} 1-#{chapters}", type: "json", formatting: "full")
  end

  @doc "Lower-case hex sha256 of iodata."
  @spec sha256(iodata()) :: String.t()
  def sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  @doc """
  One checksum for the whole download: sha256 over `code<TAB>sha256<LF>`
  for each book's response in canonical order.
  """
  @spec digest([{String.t(), String.t()}]) :: String.t()
  def digest(book_sha256s) do
    book_sha256s |> Enum.map(fn {code, sha256} -> [code, ?\t, sha256, ?\n] end) |> sha256()
  end

  @doc """
  The rows of one book's API response (a JSON list of
  `%{"chapter", "verse", "text"}`), in the response's order; the
  references the response gives without text (`empty`); and the headings
  dropped, `{reference, class, text}`.
  """
  @spec book_rows({String.t(), String.t(), pos_integer()}, [map()]) :: %{
          rows: [row()],
          empty: [String.t()],
          headings: [{String.t(), String.t(), String.t()}]
        }
  def book_rows({code, _name, chapters}, items) do
    parsed =
      Enum.map(items, fn item ->
        chapter = String.to_integer(item["chapter"])
        verse = String.to_integer(item["verse"])
        where = reference(code, chapter, verse)

        if chapter not in 1..chapters//1 or verse < 1 do
          raise ArgumentError, "#{where}: outside the book"
        end

        verse_text = parse(item["text"], where)

        if verse_text.superscription != "" and not (code == "Psa" and verse == 1) do
          raise ArgumentError, "#{where}: a superscription outside a Psalm's first verse"
        end

        rows =
          [{0, verse_text.superscription}, {verse, verse_text.text}]
          |> Enum.reject(fn {_verse, text} -> text == "" end)
          |> Enum.map(fn {verse, text} -> row(code, chapter, verse, text) end)

        %{
          rows: rows,
          empty: if(verse_text.text == "", do: [where], else: []),
          headings: Enum.map(verse_text.headings, fn {class, text} -> {where, class, text} end)
        }
      end)

    rows = Enum.flat_map(parsed, & &1.rows)
    duplicates = rows |> Enum.frequencies_by(& &1.reference) |> Enum.filter(&(elem(&1, 1) > 1))
    if duplicates != [], do: raise(ArgumentError, "repeated verses #{inspect(duplicates)}")

    %{
      rows: rows,
      empty: Enum.flat_map(parsed, & &1.empty),
      headings: Enum.flat_map(parsed, & &1.headings)
    }
  end

  @doc """
  The plain text of one verse's API markup: the Psalm superscription (`""`
  when there is none), the verse text, and the dropped headings as
  `{class, text}`. `where` names the verse in errors.
  """
  @spec parse(String.t(), String.t()) :: %{
          superscription: String.t(),
          text: String.t(),
          headings: [{String.t(), String.t()}]
        }
  def parse(html, where \\ "NET") do
    tokens = Regex.scan(Regex.compile!("<[^>]*>|[^<]+"), html) |> List.flatten()

    state =
      Enum.reduce(
        tokens,
        %{paragraph: :text, stack: [], text: [], superscription: [], headings: []},
        fn
          "<" <> _rest = tag, state -> tag(state, tag, where)
          text, state -> add(state, decode(text, where))
        end
      )

    if state.stack != [] do
      raise ArgumentError, "#{where}: unclosed #{inspect(state.stack)} in #{inspect(html)}"
    end

    %{
      superscription: finish(state.superscription),
      text: finish(state.text),
      headings:
        state.headings
        |> Enum.reverse()
        |> Enum.map(fn {class, text} -> {class, finish(text)} end)
    }
  end

  defp tag(state, tag, where) do
    case Regex.run(Regex.compile!(~S"^<(/?)([a-z]+)\s*(.*?)\s*(/?)>$", "s"), tag,
           capture: :all_but_first
         ) do
      ["", "p", attributes, _self] -> paragraph(state, attributes, tag, where)
      ["/", "p", "", ""] -> %{state | paragraph: :text} |> add(" ")
      ["", "br", _attributes, _self] -> add(state, " ")
      ["", "n", _attributes, "/"] -> state
      ["", name, attributes, ""] when name in @inline -> open(state, name, attributes, tag, where)
      ["/", name, "", ""] when name in @inline -> close(state, name, where)
      _other -> raise ArgumentError, "#{where}: unexpected markup #{tag}"
    end
  end

  defp paragraph(state, attributes, tag, where) do
    state =
      case class(attributes) do
        "psasuper" ->
          %{state | paragraph: :superscription}

        class when class in @text_paragraphs ->
          %{state | paragraph: :text}

        class when class in @heading_paragraphs ->
          %{state | paragraph: :heading, headings: [{class, []} | state.headings]}

        _other ->
          raise ArgumentError, "#{where}: unexpected paragraph #{tag}"
      end

    add(state, " ")
  end

  defp open(state, "span", attributes, tag, where) do
    case class(attributes) do
      "smcaps" -> %{state | stack: [:smcaps | state.stack]}
      "hebrew" when state.paragraph == :heading -> %{state | stack: [:span | state.stack]}
      _other -> raise ArgumentError, "#{where}: unexpected #{tag}"
    end
  end

  defp open(state, name, _attributes, _tag, _where), do: %{state | stack: [name | state.stack]}

  defp close(%{stack: [top | rest]} = state, "span", _where) when top in [:smcaps, :span] do
    %{state | stack: rest}
  end

  defp close(%{stack: [name | rest]} = state, name, _where), do: %{state | stack: rest}

  defp close(state, name, where) do
    raise ArgumentError, "#{where}: </#{name}> closes #{inspect(state.stack)}"
  end

  defp add(state, text) do
    text = if :smcaps in state.stack, do: String.upcase(text), else: text

    case state.paragraph do
      :text ->
        %{state | text: [state.text | text]}

      :superscription ->
        %{state | superscription: [state.superscription | text]}

      :heading ->
        [{class, heading} | rest] = state.headings
        %{state | headings: [{class, [heading | text]} | rest]}
    end
  end

  defp class(attributes) do
    # The service sometimes doubles the quotes (class=""smcaps"", 27 times).
    case Regex.run(Regex.compile!(~S|class="+([^"]*)"+|), attributes, capture: :all_but_first) do
      [class] -> class
      nil -> nil
    end
  end

  @entities %{"amp" => "&", "lt" => "<", "gt" => ">", "quot" => "\"", "apos" => "'"}

  defp decode(text, where) do
    Regex.replace(Regex.compile!("&(#?[A-Za-z0-9]+);"), text, fn _all, entity ->
      case {Map.fetch(@entities, entity), entity} do
        {{:ok, character}, _entity} -> character
        {:error, "#" <> number} -> <<String.to_integer(number)::utf8>>
        _unknown -> raise ArgumentError, "#{where}: unknown entity &#{entity};"
      end
    end)
  end

  defp finish(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> then(&Regex.replace(Regex.compile!("[ \\t\\r\\n]+"), &1, " "))
    |> String.trim()
  end

  @doc ~S|A pack reference: `reference("Psa", 3, 0)` is `"Psa.3.0"`.|
  @spec reference(String.t(), pos_integer(), non_neg_integer()) :: String.t()
  def reference(book, chapter, verse), do: "#{book}.#{chapter}.#{verse}"

  defp row(book, chapter, verse, text) do
    %{
      reference: reference(book, chapter, verse),
      book: book,
      chapter: chapter,
      verse: verse,
      text: text
    }
  end

  @doc "Every book's `book_rows/2`, joined in canonical order, given `%{code => decoded response}`."
  @spec rows(%{String.t() => [map()]}) :: %{
          rows: [row()],
          empty: [String.t()],
          headings: [{String.t(), String.t(), String.t()}]
        }
  def rows(responses) do
    books =
      Enum.map(Books.all(), fn {code, _name, _chapters} = book ->
        book_rows(book, Map.fetch!(responses, code))
      end)

    %{
      rows: Enum.flat_map(books, & &1.rows),
      empty: Enum.flat_map(books, & &1.empty),
      headings: Enum.flat_map(books, & &1.headings)
    }
  end
end
