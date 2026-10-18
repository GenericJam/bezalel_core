defmodule Bezalel.Agent.Pushback do
  @moduledoc """
  Pushback: a second model reviews a finished reply the way a colleague
  reviews code, and the model that answered (the lead) answers the review.
  The user picks the critic in Settings ("Pushback from",
  `Bezalel.Study.Preferences`' `pushback_model`, none by default).

  **One round per reply.** `start/3` takes the conversation's last reply
  (`target/1`): the question, the tool results it drew on (with their
  Source lines) and the answer go to the critic with the study critic's
  brief (`critic_prompt/0`) through `Rho.Consult` (`purpose: "critique"`,
  on the conversation's loop: the critique streams to the loop's
  subscribers as `consult_*` events, its cost is recorded in the session,
  and stopping the loop stops it). The critique is then stored as the
  critic's own message (rho's attributed `model_message` entry) and the
  lead is prompted with it, with `instruction/0`: respond to each point,
  revise where it's right, stand its ground with reasons where it isn't.
  The lead's answer to the critique is a reply that can't be pushed back
  on, and a reply that has had its pushback can't have another.

  **Three ways in.** A per-conversation switch (the host keeps it) calls
  `auto/3` after each finished reply; a Pushback button on the last reply
  (`offered?/2` says where to show it) calls `start/3`; and the user can
  ask in words ("have Gemini push back"): the system prompt's rule
  (`Bezalel.Study.Prompt.system_prompt/2`, `ask_model: true`) has the lead
  call rho's `ask_model` tool itself, within its turn.

  The chat: `Bezalel.Agent.Reply` folds the critique into a CONSULT block
  ahead of the lead's answer; stored, the critique is a `:consult`
  `Bezalel.Library.Message`; `title/2` names either ("Pushback · Gemini 3
  Pro").

  The host points rho's consult system prompt here, so a critique the
  lead asks for in words gets the same brief: `config :rho,
  :consult_system, {Bezalel.Agent.Pushback, :system, []}`.
  """

  alias Bezalel.Agent.Reply
  alias Bezalel.Library.{Message, Transcript}
  alias Rho.{Loop, Session}

  @purpose "critique"

  @critic """
  You review another model's answer in Bezalel, a Bible-study companion, as a careful colleague reviews code: you look for what is wrong, weak or missing. You don't rewrite the answer.

  You get the user's question, the results of the study tools the answer drew on (the biblical text, lexicons, notes, background, ancient sources, each with its Source line) and the answer.

  Check:

  1. **Claims against the sources.** Does each claim match what the tool results say? A quotation that differs from the tool's wording, a reference that doesn't say what the answer says it does, something presented as from a source that isn't in it.
  2. **Citations.** A citation or link that doesn't support the claim it is attached to, a link no tool gave, a Bible quotation without its translation label.
  3. **Text and language.** The Hebrew, Aramaic and Greek: a word's meaning, form, parsing or semantic range, a Strong's number, an etymology taken for meaning, a textual variant misdescribed.
  4. **Missing or one-sided perspectives.** One reading presented as the only one where Jewish, Catholic, Orthodox, Protestant or critical scholarship read the text otherwise; a view not credited to those who hold it.
  5. **Overreach.** Conclusions beyond the evidence: certainty where the evidence is thin or contested, a hypothesis stated as fact, a parallel taken for dependence, a verse used as a proof text out of its context or genre.

  Take no confessional side yourself: the question is whether the answer is accurate, credited and fair to the range of readings, not whether it reaches the conclusion you prefer. Raise only what you can show; say so when you are unsure.

  Answer with a numbered list, most serious first. Each point: its severity (**major**, **minor** or **nit**), what the answer says (quote it briefly), what is wrong, and your evidence (a tool result, a reference, a reading it left out). A sentence or two per point. No rewrite, no praise, no summary. If there is nothing worth raising, say "No pushback." and why, in one sentence.
  """

  @instruction "Respond to each point: revise where it's right, stand your ground with reasons " <>
                 "where it isn't. Check with the tools where a point turns on the evidence. " <>
                 "If anything changes, end with the corrected answer."

  # What of each tool result the critic gets: enough to check a claim
  # against, not a whole lexicon entry.
  @result_chars 4_000
  @results_chars 24_000

  @typedoc """
  The reply to push back on: the `question` entry, the reply's `entries`
  (its turns and tool results) and its `answer` (the SUMMARY's text).
  """
  @type target :: %{question: Session.entry(), entries: [Session.entry()], answer: String.t()}

  @doc "The critic's system prompt: the study's code review."
  @spec critic_prompt() :: String.t()
  def critic_prompt, do: @critic

  @doc "What the lead is asked to do with the critique (rho's `:instruction`)."
  @spec instruction() :: String.t()
  def instruction, do: @instruction

  @doc """
  rho's consult system prompt for `purpose` (`config :rho,
  :consult_system, {Bezalel.Agent.Pushback, :system, []}`): the critic's
  brief for a critique, rho's default (nil) for anything else.
  """
  @spec system(String.t()) :: String.t() | nil
  def system(@purpose), do: @critic
  def system(_purpose), do: nil

  @doc """
  A model's name as the chat shows it: the catalog's (`Rho.Models`),
  else the spec's model id (`"google:gemini-3-pro"` → `"gemini-3-pro"`).
  """
  @spec label(String.t()) :: String.t()
  def label(model) do
    with {:ok, provider} <- Rho.Auth.provider_for_model(model),
         %{name: name} <-
           Enum.find(Rho.Models.catalog(provider), &Rho.Models.same?(&1.spec, model)) do
      name
    else
      _ -> model |> String.split(":", parts: 2) |> List.last()
    end
  end

  @doc """
  The title of another model's message or a CONSULT block: "Pushback ·
  Gemini 3 Pro" for a critique, "Second opinion · …" for a second
  opinion, else the purpose itself.
  """
  @spec title(String.t(), String.t()) :: String.t()
  def title(model, purpose) do
    kind =
      case purpose do
        @purpose -> "Pushback"
        "second_opinion" -> "Second opinion"
        other -> other |> String.replace("_", " ") |> String.capitalize()
      end

    "#{kind} · #{label(model)}"
  end

  @doc """
  Whether the chat offers Pushback on `message` among `messages` (the
  conversation's, `Bezalel.Library.Transcript.messages/2`): it is the last
  message, a reply with an answer, and not the lead's answer to another
  model's message.
  """
  @spec offered?([Message.t()], Message.t()) :: boolean()
  def offered?(messages, %Message{role: :agent, id: id} = message) do
    case Enum.reverse(messages) do
      [%Message{id: ^id} | before] ->
        answered?(message) and not match?([%Message{role: :consult} | _], before)

      _ ->
        false
    end
  end

  def offered?(_messages, _message), do: false

  defp answered?(%Message{blocks: blocks}), do: Enum.any?(blocks, &(&1["id"] == "sum"))

  @doc """
  The reply `branch` (a session's active branch) would push back on: its
  last, if it finished with an answer. `{:error, :no_reply}` when there
  is none (no answer yet, a failed or stopped one, a reply Bezalel wrote
  itself), `{:error, :pushed_back}` when the last reply answers another
  model's message or the branch ends with one (one round per reply).
  """
  @spec target([Session.entry()]) :: {:ok, target()} | {:error, :no_reply | :pushed_back}
  def target(branch) do
    rev = Enum.reverse(branch)

    case Enum.split_while(rev, &(not boundary?(&1))) do
      {_after, []} ->
        {:error, :no_reply}

      {_after, [%{"type" => "custom_message"} | _]} ->
        {:error, :pushed_back}

      {after_rev, [question | _]} ->
        entries = after_rev |> Enum.reverse() |> Enum.filter(&turn?/1)
        reply(question, entries)
    end
  end

  defp reply(question, entries) do
    with %{"message" => %{"stopReason" => stop} = last} when stop in ["stop", "length"] <-
           List.last(entries),
         false <- Map.has_key?(last, "bezalel"),
         answer when answer != "" <- answer([question | entries]) do
      {:ok, %{question: question, entries: entries, answer: answer}}
    else
      _ -> {:error, :no_reply}
    end
  end

  defp answer(entries) do
    entries
    |> Transcript.messages("")
    |> Enum.flat_map(& &1.blocks)
    |> Enum.find_value("", &(&1["id"] == "sum" and &1["text"]))
  end

  defp boundary?(%{"type" => "message", "message" => %{"role" => "user"}}), do: true
  defp boundary?(%{"type" => "custom_message"} = entry), do: Session.attribution(entry) != nil
  defp boundary?(_entry), do: false

  defp turn?(%{"type" => "message", "message" => %{"role" => role}}),
    do: role in ["assistant", "toolResult"]

  defp turn?(_entry), do: false

  @doc """
  What the critic reads for `target`: the question (its attachments go
  along by reference, `attachments/1`), each tool call with its result
  (cut to #{@result_chars} characters each, #{@results_chars} in all) and
  the answer.
  """
  @spec brief(target()) :: String.t()
  def brief(%{question: %{"message" => q}, entries: entries, answer: answer}) do
    attached =
      case Session.attachments(q) do
        [] -> ""
        list -> "\n\n(Attached: #{Enum.map_join(list, ", ", &(&1["name"] || &1["ref"]))}.)"
      end

    question = String.trim(Session.typed(q)) <> attached

    Enum.join(
      [
        "## The user's question\n\n" <> question,
        "## The tool results the answer drew on\n\n" <> results(entries),
        "## The answer\n\n" <> String.trim(answer),
        "Push back on the answer, as your brief says."
      ],
      "\n\n"
    )
  end

  @doc "The question's attachments by reference, for the critic to see them too."
  @spec attachments(target()) :: [map()]
  def attachments(%{question: %{"message" => q}}),
    do: for(%{"ref" => ref} = a <- Session.attachments(q), is_binary(ref), do: a)

  defp results(entries) do
    calls =
      for %{"message" => %{"role" => "assistant"} = m} <- entries,
          call <- Session.tool_calls(m),
          into: %{},
          do: {call["id"], call}

    shown =
      for %{"message" => %{"role" => "toolResult"} = m} <- entries do
        call = calls[m["toolCallId"]] || %{}
        args = call["arguments"] || %{}
        head = "### #{m["toolName"]}(#{Jason.encode!(args)})"
        text = m["content"] |> Session.text() |> String.trim() |> clip(@result_chars)
        error = if m["isError"] == true, do: "Error: ", else: ""
        head <> "\n\n" <> error <> text
      end

    case shown do
      [] -> "(None: the answer called no tools.)"
      shown -> shown |> Enum.join("\n\n") |> clip(@results_chars)
    end
  end

  defp clip(text, max) do
    if String.length(text) > max,
      do: String.slice(text, 0, max) <> "\n\n[… cut]",
      else: text
  end

  @doc """
  Pushes back on the last reply of `loop`'s conversation with `model` (a
  rho model spec; the user's "Pushback from"). Checks what can be checked
  at once and answers `{:error, text}` for the user: no critic chosen, the
  critic's provider not signed in or not allowed (`Rho.Consult.allowed/1`:
  "add a Gemini key"), a reply still running, nothing to push back on, a
  reply already pushed back. Then runs in a task (`{:ok, pid}`) under
  `opts[:task_supervisor]` (rho's `Rho.TaskSup` by default): the critique,
  then the lead's answer, both on the loop's event stream. A consult that
  fails ends there (its `consult_end` carries the error); the critique
  arrives while the loop is busy (the user asked something meanwhile), it
  waits in the loop's follow-up queue.

  `opts[:consult]` is added to `Rho.Consult.run/3`'s options.
  """
  @spec start(GenServer.server(), String.t() | nil, keyword()) ::
          {:ok, pid()} | {:error, String.t()}
  def start(loop, model, opts \\ [])

  def start(_loop, nil, _opts),
    do: {:error, "Choose a model to push back in Settings (Pushback from)."}

  def start(loop, model, opts) do
    with :ok <- allowed(model),
         {:ok, target} <- idle_target(loop) do
      supervisor = opts[:task_supervisor] || Rho.TaskSup
      Task.Supervisor.start_child(supervisor, fn -> run(loop, model, target, opts) end)
    end
  end

  @doc """
  The automatic switch: after a reply ends (its `Bezalel.Agent.Reply`,
  folded through `:agent_end`), pushes back on it with `model` when it
  finished with an answer that can be pushed back on (`start/3`);
  `:skip` when there's no critic, the reply failed or was stopped, or it
  was itself the answer to a pushback.
  """
  @spec auto(GenServer.server(), Reply.t(), String.t() | nil, keyword()) ::
          {:ok, pid()} | :skip | {:error, String.t()}
  def auto(loop, reply, model, opts \\ [])

  def auto(_loop, _reply, nil, _opts), do: :skip

  def auto(loop, %Reply{status: :done}, model, opts) do
    case idle_target(loop) do
      {:ok, _target} -> start(loop, model, opts)
      {:error, _} -> :skip
    end
  end

  def auto(_loop, _reply, _model, _opts), do: :skip

  defp allowed(model) do
    case Rho.Consult.allowed(model) do
      :ok -> :ok
      {:error, why} -> {:error, "#{label(model)} can't push back: #{why}"}
    end
  end

  defp idle_target(loop) do
    snapshot = Loop.snapshot(loop)

    cond do
      snapshot.status != :idle ->
        {:error, "Wait for the answer to finish, then ask for pushback."}

      Map.get(snapshot, :consults, []) != [] ->
        {:error, "Pushback is already on its way."}

      true ->
        case target(snapshot.entries) do
          {:ok, target} -> {:ok, target}
          {:error, :no_reply} -> {:error, "There's no finished answer to push back on yet."}
          {:error, :pushed_back} -> {:error, "This answer has had its pushback (one round each)."}
        end
    end
  end

  defp run(loop, model, target, opts) do
    consult_opts =
      [
        purpose: @purpose,
        system: @critic,
        loop: loop,
        attachments: attachments(target)
      ] ++ (opts[:consult] || [])

    case Rho.Consult.run(model, brief(target), consult_opts) do
      {:ok, %{text: text}} -> answer(loop, model, text)
      {:error, _} -> :ok
    end
  end

  # The critique, attributed to the critic, for the lead to answer. A loop
  # released meanwhile (the user left) has no one to answer it.
  defp answer(loop, model, text) do
    opts = [attribution: {:model, model, @purpose}, instruction: @instruction]

    case Loop.prompt(loop, text, opts) do
      {:error, :running} -> Loop.follow_up(loop, text, opts)
      other -> other
    end
  catch
    :exit, _ -> :ok
  end
end
