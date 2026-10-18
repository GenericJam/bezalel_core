defmodule Bezalel.Agent.Reply do
  @moduledoc """
  A live reply as it streams: rho's loop events (`Rho.Events`) folded into
  the design's blocks. Each model call's thinking is a THINKING block, each
  tool call a TOOL CALL block (its name and arguments, the result on
  expand), and the answer the SUMMARY. Text the model writes in a call
  that also calls tools is working narration: it joins that call's
  THINKING. A `lookup_verse` or `word_study` result that names a passage
  becomes the passage card (`Bezalel.Agent.Card`).

  Every study tool's result carries the sources it rests on
  (`Bezalel.Study.Citation`); the reply collects them, without repeats, in
  `citations`, and `sources/1` marks the ones its answer links.

  Pictures in a turn or a tool result are listed in `images` (stored
  inline) and `materials` (by reference: a `draw_image` drawing).

  **Another model** (`Rho.Consult`'s events). A pushback
  (`Bezalel.Agent.Pushback`) is a reply of its own: the critic's
  critique streams into `consult` (`%{model, purpose, text, status,
  error, entry}`: rho's out-of-turn `consult_*` events, `call_id` nil)
  and leads the blocks as a CONSULT block, then the lead model's answer
  to it follows as usual. A failed or stopped consult ends the reply
  (`status` `:error` or `:stopped`); a done one waits for the answer.
  Its `model_message` entry, once stored, is in `seen` like the reply's
  other entries (the chat leaves it to the stream while it runs). A
  model the lead asks itself (rho's `ask_model` tool) is a CONSULT block
  in place of that TOOL CALL, its text streaming in as it comes.

  No file I/O: the host app keeps one per conversation with a reply in
  flight. The loop writes the reply to the conversation's session as it
  goes; once stored, `Bezalel.Library.Transcript` rebuilds it with this same
  fold over its entries.
  """

  alias Bezalel.Agent.{Card, Patterns}
  alias Bezalel.Library.Transcript
  alias Bezalel.Study.{Citation, Citations}
  alias Rho.Session

  @type status :: :running | :done | :stopped | :error

  @type t :: %__MODULE__{
          conversation_id: integer(),
          session_id: String.t() | nil,
          model: String.t(),
          status: status(),
          turn: non_neg_integer(),
          items: [map()],
          text: String.t(),
          summary: String.t(),
          card: Card.t() | nil,
          citations: [Citation.t()],
          images: [Bezalel.Library.Message.image()],
          materials: [Bezalel.Library.Message.material()],
          seen: [String.t()],
          kept: [String.t()],
          pending: [String.t()],
          retry: String.t() | nil,
          error: String.t() | nil,
          reason: atom() | nil,
          consult: consult() | nil
        }

  @typedoc "Another model's message as it streams: `status` `:running`, `:ok`, `:error` or `:stopped`."
  @type consult :: %{
          model: String.t(),
          purpose: String.t(),
          text: String.t(),
          status: :running | :ok | :error | :stopped,
          error: String.t() | nil,
          entry: String.t() | nil
        }

  defstruct [
    :conversation_id,
    :session_id,
    :model,
    status: :running,
    turn: 0,
    items: [],
    text: "",
    summary: "",
    card: nil,
    citations: [],
    images: [],
    materials: [],
    seen: [],
    kept: [],
    pending: [],
    retry: nil,
    error: nil,
    reason: nil,
    consult: nil
  ]

  # A header line longer than this (about one line on a phone) is cut; the
  # whole text is then the rest, so nothing hides behind the cut.
  @first_max 32
  # Lines and characters of a tool result shown under its call.
  @result_lines 6
  @result_chars 500

  @doc "A reply about to stream in `conversation_id` from `model`."
  @spec new(integer(), String.t(), String.t() | nil) :: t()
  def new(conversation_id, model, session_id \\ nil),
    do: %__MODULE__{conversation_id: conversation_id, model: model, session_id: session_id}

  @doc "A reply that failed before it started (no credential): shown as its error."
  @spec failed(integer(), String.t(), String.t()) :: t()
  def failed(conversation_id, model, error),
    do: %{new(conversation_id, model) | status: :error, error: error}

  @doc "Folds one loop event in."
  @spec apply(t(), map()) :: t()
  def apply(r, %{type: :turn_start, turn: turn}), do: %{r | turn: turn, text: ""}

  def apply(r, %{type: :message_update, kind: :thinking, delta: delta}),
    do: %{update_think(r, &(&1 <> delta)) | retry: nil}

  def apply(r, %{type: :message_update, kind: :text, delta: delta}),
    do: %{r | text: r.text <> delta, retry: nil}

  def apply(r, %{type: :message_end, entry: %{"message" => %{"role" => "assistant"} = m} = entry}) do
    r = r |> saw(entry) |> add_images(entry)

    cond do
      m["stopReason"] == "error" ->
        %{r | error: r.error || m["errorMessage"]}

      Session.tool_calls(m) != [] and String.trim(r.text) != "" ->
        r |> update_think(&join(&1, r.text)) |> Map.put(:text, "")

      true ->
        %{r | summary: join(r.summary, r.text), text: ""}
    end
  end

  def apply(r, %{type: :message_end, entry: %{"message" => %{"role" => "toolResult"}} = entry}),
    do: r |> saw(entry) |> add_images(entry)

  # Another model's message stored (a pushback's critique): one of this
  # reply's entries, and the consult's text as stored.
  def apply(r, %{type: :message_end, entry: %{"type" => "custom_message"} = entry}) do
    case Session.attribution(entry) do
      %{model: model, purpose: purpose} ->
        consult = r.consult || %{model: model, purpose: purpose, status: :ok, error: nil}

        consult =
          Map.merge(consult, %{text: Session.text(entry["content"]), entry: entry["id"]})

        %{saw(r, entry) | consult: consult}

      nil ->
        notice(r, entry)
    end
  end

  def apply(r, %{type: :consult_start, call_id: nil, model: model, purpose: purpose}) do
    consult = %{
      model: model,
      purpose: purpose,
      text: "",
      status: :running,
      error: nil,
      entry: nil
    }

    %{r | consult: consult}
  end

  def apply(r, %{type: :consult_start, call_id: id, model: model, purpose: purpose}),
    do: update_tool(r, id, &Map.put(&1, :consult, %{model: model, purpose: purpose, text: ""}))

  def apply(%{consult: %{} = c} = r, %{type: :consult_delta, call_id: nil, kind: :text, delta: d}),
      do: %{r | consult: %{c | text: c.text <> d}}

  def apply(r, %{type: :consult_delta, call_id: id, kind: :text, delta: delta}) when id != nil do
    update_tool(r, id, fn
      %{consult: %{} = c} = item -> %{item | consult: %{c | text: c.text <> delta}}
      item -> item
    end)
  end

  def apply(r, %{type: :consult_end, call_id: nil} = event) do
    consult =
      Map.merge(
        r.consult || %{model: event.model, purpose: event.purpose, entry: nil},
        %{status: event.status, error: event[:error], text: event[:text] || ""}
      )

    r = %{r | consult: consult}

    case event.status do
      :ok -> r
      :stopped -> %{r | status: :stopped, reason: :stopped}
      :error -> %{r | status: :error, error: r.error || consult_error(consult)}
    end
  end

  # The message being streamed is dropped (a retry, or an overflow
  # compaction): its thinking and text with it.
  def apply(r, %{type: :retry, attempt: attempt, error: error}),
    do: %{discard_attempt(r) | retry: "Retrying (#{attempt}): #{error}"}

  def apply(r, %{type: :compaction_start, reason: :overflow}), do: discard_attempt(r)

  def apply(r, %{type: :tool_execution_start, id: id, name: name, arguments: args}) do
    item = %{
      id: "tool-#{id}",
      kind: :tool,
      name: name,
      args: args,
      result: nil,
      error: false,
      card: nil,
      consult: asked(name, args)
    }

    %{r | items: r.items ++ [item]}
  end

  def apply(r, %{type: :tool_execution_end, id: id, name: name} = event) do
    # Replayed from the session (`Bezalel.Library.Transcript`), the card
    # and citations are the ones kept with the result; live, they're the
    # details'.
    {card, citations} =
      cond do
        event.is_error -> {nil, []}
        Map.has_key?(event, :card) -> {event.card, event[:citations] || []}
        true -> {Card.from_tool(name, event[:details]), live_citations(event[:details])}
      end

    items =
      Enum.map(r.items, fn
        %{id: "tool-" <> ^id} = item ->
          item = %{item | result: event.text, error: event.is_error, card: card}
          answered(item)

        item ->
          item
      end)

    %{
      r
      | items: items,
        card: pick_card(r.card, card, name),
        citations: Citations.dedupe(r.citations ++ citations)
    }
  end

  def apply(r, %{type: :turn_end, error: error}) when is_binary(error),
    do: %{r | error: r.error || error}

  def apply(r, %{type: :agent_end, reason: reason}) do
    status =
      cond do
        r.error != nil or reason == :error -> :error
        reason == :stopped -> :stopped
        true -> :done
      end

    %{r | status: status, reason: reason, retry: nil, summary: join(r.summary, r.text), text: ""}
  end

  def apply(r, _event), do: r

  @doc "Whether the reply is still streaming."
  @spec running?(t() | nil) :: boolean()
  def running?(%__MODULE__{status: :running}), do: true
  def running?(_reply), do: false

  @doc "Whether there's anything to show: a block, a card, a picture or a material."
  @spec any?(t()) :: boolean()
  def any?(r), do: blocks(r) != [] or r.card != nil or r.images != [] or r.materials != []

  @doc """
  The sources the reply's tools consulted (`citations`), each marked
  `cited` when the answer so far links it (`Bezalel.Study.Citations.mark/2`),
  in the order the tools returned them. A sources list groups them with
  `Bezalel.Study.Citations.by_work/1`.
  """
  @spec sources(t()) :: [Citation.t()]
  def sources(r), do: Citations.mark(r.citations, join(r.summary, r.text))

  defp live_citations(%{citations: citations}) when is_list(citations),
    do: for(c <- citations, c = Citation.from_map(c), do: c)

  defp live_citations(_details), do: []

  @doc """
  Starts over after the steering message `text` was injected: the reply so
  far is done (the chat shows it from the session now: its entries move to
  `kept`), the run goes on as a new reply. `pending` loses `text`.
  """
  @spec continue(t(), String.t()) :: t()
  def continue(r, text) do
    %{
      new(r.conversation_id, r.model, r.session_id)
      | turn: r.turn,
        pending: r.pending -- [text],
        kept: r.kept ++ r.seen
    }
  end

  @doc """
  The blocks in the design's shape (`%{"id", "type", "first", "rest"}`, plus
  `"cut" => true` when `first` is a cut-short header and `rest` the whole
  text): another model's message first when this reply answers one (a
  pushback's CONSULT block), then each call's THINKING and TOOL CALLs in
  order (a model the lead asked, `ask_model`, as a CONSULT block), then
  the SUMMARY (with the text still streaming).

  `first` is a plain line (`header/1`); `rest` is Markdown, the model's or
  the tool's own, which the chat renders. THINKING, SUMMARY and CONSULT
  carry the model's whole text as `"text"` (what Copy copies); a CONSULT
  block also has the consulted `"model"` (a rho model spec) and its
  `"purpose"` (`"critique"`, `"second_opinion"`, …), for its title
  (`Bezalel.Agent.Pushback.title/2`).
  """
  @spec blocks(t()) :: [map()]
  def blocks(r) do
    consult = if r.consult, do: [consult_block("consult", r.consult)], else: []

    items =
      for item <- r.items, block = item_block(item), do: block

    case String.trim(join(r.summary, r.text)) do
      "" -> consult ++ items
      summary -> consult ++ items ++ [block("sum", "SUMMARY", summary)]
    end
  end

  @doc """
  Another model's message as a CONSULT block (`blocks/1`): `consult` has
  its `model`, `purpose` and `text` (empty while it is still coming).
  """
  @spec consult_block(String.t(), %{model: String.t(), purpose: String.t(), text: String.t()}) ::
          map()
  def consult_block(id, %{model: model, purpose: purpose, text: text}) do
    b =
      case String.trim(text) do
        "" ->
          %{"id" => id, "type" => "CONSULT", "first" => "Running…", "rest" => "", "text" => ""}

        text ->
          block(id, "CONSULT", text)
      end

    Map.merge(b, %{"model" => model, "purpose" => purpose})
  end

  @doc """
  One line of Markdown as plain text, for a block's header: heading, list
  and quote marks dropped, a table row's cells joined by " · ", emphasis,
  code and strikethrough marks dropped, links and images as their text.
  """
  @spec header(String.t()) :: String.t()
  def header(line) do
    line
    |> String.trim()
    |> strip_block_marks()
    |> then(&Regex.replace(Patterns.get(:md_link), &1, "\\1"))
    |> String.replace(["**", "__", "~~", "`", "*"], "")
    |> then(&Regex.replace(Patterns.get(:md_underscore), &1, ""))
    |> String.split()
    |> Enum.join(" ")
  end

  defp strip_block_marks(line) do
    cond do
      String.starts_with?(line, "|") ->
        line |> String.trim("|") |> String.split("|") |> Enum.map_join(" · ", &String.trim/1)

      String.starts_with?(line, ["```", "~~~"]) ->
        ""

      true ->
        Regex.replace(Patterns.get(:md_block_mark), line, "")
    end
  end

  defp item_block(%{kind: :think, id: id, text: text}) do
    case String.trim(text) do
      "" -> nil
      text -> block(id, "THINKING", text)
    end
  end

  # A model the lead asked (ask_model), unless the call failed: its text.
  defp item_block(%{kind: :tool, consult: %{} = consult, error: false} = item),
    do: consult_block(item.id, consult)

  defp item_block(%{kind: :tool} = item) do
    %{"id" => item.id, "type" => "TOOL CALL", "first" => call_label(item), "rest" => result(item)}
  end

  # `"cut"` marks a header cut short: `rest` then holds the whole text.
  defp block(id, type, text) do
    {first, rest, cut?} = split(text)
    b = %{"id" => id, "type" => type, "first" => first, "rest" => rest, "text" => text}
    if cut?, do: Map.put(b, "cut", true), else: b
  end

  # The header: the first line when it's a block of its own (a heading, a
  # list item, a quote), else the first sentence; the rest is what follows
  # it. A table or a code block first stays whole under its first line, as
  # does a text whose header would be long, or empty, or would leave the
  # rest's Markdown unbalanced (a link or emphasis running on past it).
  defp split(text) do
    [line | _] = String.split(text, "\n", parts: 2)

    head =
      cond do
        Regex.match?(Patterns.get(:md_block_line), line) -> line
        match = Regex.run(Patterns.get(:first_sentence), text) -> hd(match)
        true -> text
      end

    first = header(head)
    whole? = String.starts_with?(String.trim_leading(line), ["|", "```", "~~~"])

    if whole? or first == "" or String.length(first) > @first_max or
         not balanced?(strip_block_marks(String.trim(head))),
       do: {cut(text), text, true},
       else: {first, text |> String.slice(String.length(head)..-1//1) |> String.trim(), false}
  end

  defp balanced?(markdown) do
    count = &(length(String.split(markdown, &1)) - 1)
    singles = markdown |> String.replace("**", "") |> String.split("*") |> length()

    underscores =
      length(Regex.scan(Patterns.get(:md_underscore), String.replace(markdown, "__", "")))

    count.("[") == count.("]") and count.("(") == count.(")") and
      Enum.all?(["`", "~~", "**", "__"], &(rem(count.(&1), 2) == 0)) and rem(singles - 1, 2) == 0 and
      rem(underscores, 2) == 0
  end

  # The first line with words in it, plain, cut to about a line.
  defp cut(text) do
    line = text |> String.split("\n") |> Enum.map(&header/1) |> Enum.find("", &(&1 != ""))

    if String.length(line) <= @first_max do
      line
    else
      head = String.slice(line, 0, @first_max)

      case String.split(head, " ") do
        [_one] -> head <> "…"
        words -> (words |> Enum.drop(-1) |> Enum.join(" ")) <> "…"
      end
    end
  end

  defp call_label(%{name: name, args: args}) when is_map(args) do
    shown =
      Enum.map_join(args, ", ", fn {key, value} ->
        "#{key}: " <> if(is_binary(value), do: inspect(value), else: Jason.encode!(value))
      end)

    "#{name}(#{shown})"
  end

  defp call_label(%{name: name}), do: "#{name}()"

  defp result(%{result: nil}), do: "Running…"

  # A passage reads better as its verses than as the Markdown the model got.
  defp result(%{card: %{} = card}), do: "→ " <> Card.text(card)

  # The tool's Markdown as it is, its first lines: whole lines, so a table
  # row or a heading isn't cut through (a cut fence runs to the end, as
  # Markdown has it). The "…" is a paragraph of its own, or it would join a
  # table as a row.
  defp result(%{result: text, error: error}) do
    lines = text |> String.trim() |> String.split("\n")
    {shown, more?} = first_lines(lines)
    shown = if more?, do: shown <> "\n\n…", else: shown
    if error, do: "Error: " <> shown, else: shown
  end

  defp first_lines(lines) do
    {kept, _count, _chars} =
      Enum.reduce_while(lines, {[], 0, 0}, fn line, {kept, count, chars} ->
        count = if String.trim(line) == "", do: count, else: count + 1
        chars = chars + String.length(line) + 1

        if count > @result_lines or (kept != [] and chars > @result_chars),
          do: {:halt, {kept, count, chars}},
          else: {:cont, {[line | kept], count, chars}}
      end)

    shown = kept |> Enum.reverse() |> Enum.join("\n") |> String.trim_trailing()

    # A first line longer than the limit on its own (JSON, minified HTML) is
    # cut at a word.
    if String.length(shown) > @result_chars,
      do: {clip(shown), true},
      else: {shown, length(kept) < length(lines)}
  end

  defp clip(text) do
    head = String.slice(text, 0, @result_chars)

    case String.split(head, " ") do
      [_one] -> head
      words -> words |> Enum.drop(-1) |> Enum.join(" ")
    end
  end

  # A passage from lookup_verse wins over word_study's examples; the
  # latest of a kind over an earlier one.
  defp pick_card(current, nil, _name), do: current
  defp pick_card(%{"from" => "lookup_verse"} = current, _card, "word_study"), do: current
  defp pick_card(_current, card, _name), do: card

  defp update_think(r, fun) do
    id = "think-#{r.turn}"

    {items, found?} =
      Enum.map_reduce(r.items, false, fn
        %{id: ^id} = item, _found -> {%{item | text: fun.(item.text)}, true}
        item, found -> {item, found}
      end)

    items = if found?, do: items, else: items ++ [%{id: id, kind: :think, text: fun.("")}]
    %{r | items: items}
  end

  # Pictures in a model's turn or a tool's result, keyed as the stored
  # reply's are (`Bezalel.Library.Message`), and materials by reference.
  defp add_images(r, entry) do
    %{
      r
      | images: r.images ++ Transcript.images([entry], r.session_id || ""),
        materials: r.materials ++ Transcript.materials([entry])
    }
  end

  # The session entries the loop wrote for this reply so far (`seen`); the
  # chat leaves them to the stream while it runs.
  defp saw(r, %{"id" => id}), do: %{r | seen: r.seen ++ [id]}
  defp saw(r, _entry), do: r

  defp notice(r, entry) do
    r = saw(r, entry)

    if Session.notice_kind(entry) == :error,
      do: %{r | error: r.error || Session.text(entry["content"])},
      else: r
  end

  defp update_tool(r, call_id, fun) do
    id = "tool-#{call_id}"
    %{r | items: Enum.map(r.items, &if(&1.id == id, do: fun.(&1), else: &1))}
  end

  # rho's ask_model: the model asked and why, from the call's arguments.
  defp asked("ask_model", %{"model" => model} = args) when is_binary(model),
    do: %{model: model, purpose: args["purpose"] || "second_opinion", text: ""}

  defp asked(_name, _args), do: nil

  # Its result is "<model> (<purpose>):\n\n<text>": the text is the answer.
  defp answered(%{consult: %{} = c, error: false, result: result} = item) do
    text =
      case String.split(result, "\n\n", parts: 2) do
        [head, text] -> if String.ends_with?(head, "):"), do: text, else: result
        [_] -> result
      end

    %{item | consult: %{c | text: text}}
  end

  defp answered(item), do: item

  defp consult_error(%{error: error}) when is_binary(error) and error != "", do: error
  defp consult_error(%{model: model}), do: "#{model} didn't answer."

  defp discard_attempt(r) do
    id = "think-#{r.turn}"
    %{r | text: "", items: Enum.reject(r.items, &(&1.id == id))}
  end

  defp join("", b), do: b
  defp join(a, ""), do: a
  defp join(a, b), do: a <> "\n\n" <> b
end
