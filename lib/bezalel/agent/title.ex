defmodule Bezalel.Agent.Title do
  @moduledoc """
  A conversation's title and one-line summary, written by a small model
  after each finished reply and refined on the next (the topic can drift):
  what the conversations list and the conversation's header show.

  `run/4` sends the conversation so far (`transcript/1`: the questions and
  each reply's summary, the newest when it's long) with the current title
  and summary to the lead model's provider's small model (`model/1`:
  Claude Haiku, a GPT mini, Gemini Flash-Lite, ChatGPT's Luna) through
  `Rho.Consult` with no loop: the credential is rho's (`Rho.Auth`), the
  call is recorded in rho's usage record like any other, and nothing
  reaches the session or the chat. It answers a `Title:` line and a
  `Summary:` line, which `parse/1` reads and tidies; anything else (a
  refusal, a half answer, the lines without their labels, which Haiku
  writes now and then) is unreadable and the old name stays. Not JSON: req_llm
  turns a reply that is all JSON into an object part with no text
  (seen with Claude Haiku 5.5), which `Rho.Consult` reports as no answer.

  The host app runs it off the reply's path (a task after the reply is
  stored) and keeps the old title on any error, so naming never holds up
  or fails a reply. A title the user typed is the host's to protect: it
  doesn't call this for one. Why: `decisions/2026-10-19-titles.md`.
  """

  alias Bezalel.Library.Message

  @type t :: %{title: String.t(), summary: String.t()}

  @purpose "title"

  @system """
  You name a Bible-study conversation for the list of the user's conversations. Read the conversation and answer with exactly two lines and nothing else:

  Title: at most 6 words naming what the conversation is about (the passage, person, word or question at its heart, e.g. "Bezalel and the Spirit's gifts", "Ruach in Genesis 1:2"), no quotation marks, no final period
  Summary: one plain sentence of at most 20 words saying what the conversation has covered so far

  When a current title and summary are given, keep them if they still fit the whole conversation, and change them when it has moved on. Describe the conversation; don't take a side on a question it disputes.
  """

  # The provider's small models, by a fragment of their id, most wanted
  # first, matched in rho's catalog order (newest first, except ChatGPT's,
  # which keeps omp's list order: its first Luna is GPT-5.6 Luna, the one
  # the Codex backend lists as its fast model).
  @small %{
    anthropic: ["haiku"],
    openai: ["-mini", "-nano"],
    google: ["flash-lite", "flash"],
    openai_codex: ["luna"]
  }
  @not_chat ["image", "audio", "tts", "search", "realtime", "live"]

  # Options a host may pass on to `Rho.Consult.run/3`; the rest are this
  # module's (no `:loop`: nothing reaches the session or its subscribers).
  @host_options [:llm, :budget, :data_dir, :task_supervisor]

  @title_words 8
  @title_max 60
  @summary_max 200
  @message_max 1_500
  @transcript_max 12_000

  @doc "The system prompt the naming model gets."
  @spec system() :: String.t()
  def system, do: @system

  @doc """
  A conversation's name before its first title: `question`'s first line,
  cut to #{@title_max} characters. nil for a question with no words (only
  attachments).
  """
  @spec from_question(String.t() | nil) :: String.t() | nil
  def from_question(nil), do: nil

  def from_question(question) do
    case question |> String.split("\n", parts: 2) |> hd() |> String.trim() do
      "" -> nil
      line -> cut(line, @title_max)
    end
  end

  @doc """
  The small model of `lead`'s provider (a rho model spec) in rho's
  catalog, else `lead` itself.
  """
  @spec model(String.t()) :: String.t()
  def model(lead) when is_binary(lead) do
    with {:ok, provider} <- Rho.Auth.provider_for_model(lead),
         spec when is_binary(spec) <- small(provider) do
      spec
    else
      _ -> lead
    end
  end

  defp small(provider) do
    specs =
      for m <- Rho.Models.catalog(provider),
          not Enum.any?(@not_chat, &String.contains?(m.spec, &1)),
          do: m.spec

    Enum.find_value(Map.get(@small, provider, []), fn fragment ->
      Enum.find(specs, &String.contains?(&1, fragment))
    end)
  end

  @doc """
  Names the conversation of `messages` (its visible `Bezalel.Library.Message`s)
  after a reply from `lead` (a rho model spec). `current` is the title and
  summary it has (`%{title, summary}`), sent along when it has a summary
  (one this wrote; a title without one is a placeholder or the first
  question cut short). Options: `:model` (default `model(lead)`) and
  `:consult`, `Rho.Consult.run/3`'s `:llm` (a test's), `:budget`,
  `:data_dir` and `:task_supervisor` (others are ignored).

  `{:ok, %{title, summary}}`, or `{:error, reason}`: nothing to name yet
  (`:empty`), a lead that isn't a model rho calls (`:no_model`: the
  storyboard's replies), the model call's (`Rho.Consult`'s), or an answer
  that isn't a title (`{:unreadable, answer}`, its start). Blocks the caller for the model call.
  """
  @spec run(String.t() | nil, [Message.t()], map() | nil, keyword()) ::
          {:ok, t()} | {:error, term()}
  def run(lead, messages, current \\ nil, opts \\ []) do
    model = opts[:model] || (is_binary(lead) && model(lead))

    if is_binary(model) and Rho.Auth.provider_for_model(model) != :error,
      do: ask(model, transcript(messages), current, opts),
      else: {:error, :no_model}
  end

  defp ask(_model, "", _current, _opts), do: {:error, :empty}

  defp ask(model, transcript, current, opts) do
    consult =
      Keyword.merge(host_options(opts[:consult] || []),
        purpose: @purpose,
        system: @system,
        max_tokens: 1_024
      )

    with {:ok, %{text: answer}} <- Rho.Consult.run(model, prompt(transcript, current), consult) do
      case parse(answer) do
        {:ok, named} -> {:ok, named}
        {:error, :unreadable} -> {:error, {:unreadable, String.slice(answer, 0, 300)}}
      end
    end
  end

  # One of each, the first given.
  defp host_options(given),
    do: for(key <- @host_options, Keyword.has_key?(given, key), do: {key, given[key]})

  @doc "What the naming model is asked: the conversation, then the current title and summary."
  @spec prompt(String.t(), map() | nil) :: String.t()
  def prompt(transcript, current) do
    "<conversation>\n#{transcript}\n</conversation>" <> current_part(current)
  end

  defp current_part(%{title: title, summary: summary})
       when is_binary(title) and is_binary(summary) and summary != "",
       do: "\n\nCurrent title: #{title}\nCurrent summary: #{summary}"

  defp current_part(_current), do: ""

  @doc """
  The conversation as the naming model reads it, from its first question
  on: each question, each reply's summary and each critique, cut to
  #{@message_max} characters; when the whole is longer than
  #{@transcript_max}, the first question and the newest messages that fit.
  `""` when there's no question yet.
  """
  @spec transcript([Message.t()]) :: String.t()
  def transcript(messages) do
    lines =
      messages
      |> Enum.drop_while(&(line(&1) == nil or &1.role != :user))
      |> Enum.flat_map(&List.wrap(line(&1)))

    case lines do
      [] -> ""
      [first | rest] -> fit(first, rest)
    end
  end

  @gap "[…earlier messages left out…]"

  # The first question, then the newest lines that fit with it (and the
  # gap's mark, when some are left out).
  defp fit(first, rest) do
    budget = @transcript_max - String.length(first)
    all = Enum.sum_by(rest, &(String.length(&1) + 2))

    if all <= budget do
      Enum.join([first | rest], "\n\n")
    else
      kept = newest(Enum.reverse(rest), budget - String.length(@gap) - 2, [])
      Enum.join([first, @gap | kept], "\n\n")
    end
  end

  defp newest([line | older], left, kept) do
    size = String.length(line) + 2
    if size <= left, do: newest(older, left - size, [line | kept]), else: kept
  end

  defp newest([], _left, kept), do: kept

  defp line(%Message{role: :user} = m) do
    attached = for %{name: name} <- m.materials, do: "[attached: #{name}]"

    case Enum.join(Enum.reject([m.text || "" | attached], &(&1 == "")), " ") do
      "" -> nil
      text -> "User: " <> cut(text, @message_max)
    end
  end

  defp line(%Message{role: :agent, blocks: blocks}) do
    case blocks |> Enum.filter(&(&1["id"] == "sum")) |> Enum.map_join("\n", &summary/1) do
      "" -> nil
      text -> "Assistant: " <> cut(text, @message_max)
    end
  end

  defp line(%Message{role: :consult, text: text}) when is_binary(text) and text != "",
    do: "Reviewer: " <> cut(text, @message_max)

  defp line(_message), do: nil

  defp summary(%{"text" => text}), do: String.trim(text)
  defp summary(%{"cut" => true, "rest" => rest}), do: String.trim(rest)
  defp summary(%{"first" => first, "rest" => rest}), do: String.trim("#{first} #{rest}")
  defp summary(_block), do: ""

  @doc """
  The title and summary in the naming model's answer: its `Title:` and
  `Summary:` lines (any case, Markdown and list marks around them
  dropped), else, without either label, a JSON object with `title` and
  `summary`. Each is put on one line
  without Markdown or surrounding quotes; the title loses a final period
  and is cut to #{@title_words} words and #{@title_max} characters, the
  summary to #{@summary_max}. `{:error, :unreadable}` unless both are there
  (a refusal or a half answer keeps the old name and summary).
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, :unreadable}
  def parse(answer) when is_binary(answer) do
    {title, summary} = fields(answer)
    title = title |> tidy() |> trim_end(["."]) |> title_cut()
    summary = summary |> tidy() |> cut(@summary_max)

    if title == "" or summary == "",
      do: {:error, :unreadable},
      else: {:ok, %{title: title, summary: summary}}
  end

  defp fields(answer) do
    lines = answer |> String.split("\n") |> Enum.map(&(&1 |> tidy() |> unlist()))

    case {label(lines, "title:"), label(lines, "summary:")} do
      {nil, nil} -> json(answer)
      {title, summary} -> {title || "", summary || ""}
    end
  end

  # A line without the list mark before it ("- ", "* ", "1. ").
  defp unlist(line) do
    case String.split(line, " ", parts: 2) do
      [mark, rest] when mark in ["-", "*", "+", "•"] -> rest
      [mark, rest] -> if numbered?(mark), do: rest, else: line
      _ -> line
    end
  end

  defp numbered?(mark) do
    case Integer.parse(mark) do
      {_n, rest} -> rest in [".", ")"]
      :error -> false
    end
  end

  defp json(answer) do
    with {start, _} <- :binary.match(answer, "{"),
         [{stop, _} | _] <- answer |> :binary.matches("}") |> Enum.reverse(),
         {:ok, %{} = map} <- Jason.decode(binary_part(answer, start, stop - start + 1)) do
      {text(map["title"]), text(map["summary"])}
    else
      _ -> {"", ""}
    end
  end

  defp label(lines, prefix) do
    Enum.find_value(lines, fn line ->
      if String.starts_with?(String.downcase(line), prefix),
        do: line |> binary_part(byte_size(prefix), byte_size(line) - byte_size(prefix))
    end)
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  # One line, no Markdown emphasis or heading marks, no quotes around it.
  defp tidy(text) do
    text
    |> String.replace(["**", "__", "`", "#", "*"], "")
    |> String.split()
    |> Enum.join(" ")
    |> unquote_ends()
  end

  @quotes ~w(" ' “ ” ‘ ’ * _)

  defp unquote_ends(text) do
    text
    |> String.graphemes()
    |> Enum.drop_while(&(&1 in [" " | @quotes]))
    |> Enum.join()
    |> trim_end([" " | @quotes])
  end

  # `text` without any of `chars` at its end.
  defp trim_end(text, chars) do
    text
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 in chars))
    |> Enum.reverse()
    |> Enum.join()
  end

  defp title_cut(title) do
    words = String.split(title)

    title =
      if length(words) > @title_words,
        do: words |> Enum.take(@title_words) |> Enum.join(" "),
        else: title

    if String.length(title) > @title_max, do: cut(title, @title_max), else: title
  end

  # At most `max` characters, cut at a word with an ellipsis.
  defp cut(text, max) do
    if String.length(text) <= max do
      text
    else
      head = String.slice(text, 0, max - 1)

      head =
        case String.split(head, " ") do
          [_one] -> head
          words -> words |> Enum.drop(-1) |> Enum.join(" ")
        end

      trim_end(head, [" ", ",", ";", ":", "."]) <> "…"
    end
  end
end
