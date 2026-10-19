defmodule Bezalel.Library.Transcript do
  @moduledoc """
  A conversation's transcript is its rho session (`Rho.Session`, pi's
  JSONL): this module reads the chat's messages off a branch of it and
  plans the branch edits behind Delete and Undo. No file I/O; the host app does
  the reading and writing.

  **Messages.** On the active branch, each user `message` entry is a user
  message, and each attributed `model_message` entry (another model's
  message, `Rho.Session.attribution/1`: a pushback's critique,
  `Bezalel.Agent.Pushback`) a `:consult` message; the entries between two
  of these (the model's turns, tool results, the loop's notices) are one
  reply (`Bezalel.Library.Message`), so the reply after a critique is the
  lead model's answer to it.
  A live reply's blocks are rebuilt from its entries by the fold that drew
  it while it streamed (`Bezalel.Agent.Reply`): each turn's thinking, each
  tool call with its result, the answer as the SUMMARY; its passage card
  and the sources its tools consulted come from the tool results' kept
  `details` (`Bezalel.Agent.Details.keep_details/2`; a session from before
  citations kept the bare card there, which reads as a card with no
  sources). A reply Bezalel wrote itself (the storyboard's, or one
  moved over from the old messages table) is one assistant message whose
  text is its summary, for the model, and whose `"bezalel"` field holds
  what the chat shows (`blocks`, `passage`, `card`, `image`, `model`);
  pi and rho ignore the field.

  **Delete and Undo are branch moves.** Deleting messages branches from
  the entry before the first of them and copies the entries after it,
  minus the deleted ones, onto the new branch (nothing to copy when it was
  the last message). The old branch stays in the file. Undo goes back to
  the branch before the delete, plus copies of anything added since. A
  move with nothing to copy appends a `custom` entry (`"bezalel.branch"`)
  under the entry it moves to, since the last entry in the file is the
  leaf; `custom` entries never reach a model.

  **Merging two copies.** When the phone and the website both added to a
  conversation while apart, `merge/3` plans the phone's (canonical) file
  taking the website's turns too: the branch that began later goes after
  the other's tip as copies, so the active branch holds both in order,
  then a notice says how many came from the computer. A Delete or Undo on
  the website meanwhile wins over the common part (its copies of common
  entries are recognised as such, not taken for new turns). Same technique
  as Delete: nothing is rewritten, the originals stay on an inactive branch.
  """

  alias Bezalel.Agent.Details
  alias Bezalel.Agent.Reply
  alias Bezalel.Library.Message
  alias Bezalel.Materials
  alias Rho.Session

  @marker "bezalel.branch"

  # ── Entries Bezalel writes ───────────────────────────────────────────────

  @doc """
  A user message entry; `opts` as `Rho.Session.user/2` takes them
  (`:attachments`: `Bezalel.Materials.attachments/4`'s, by reference).
  """
  @spec user(String.t(), keyword()) :: Session.entry()
  def user(text, opts \\ []), do: Session.user(text, opts)

  @doc """
  A reply Bezalel writes itself: `attrs` has `:blocks`, and optionally
  `:passage`, `:card`, `:image`, `:model` (`"storyboard"` by default) and
  `:at` (a `DateTime`, for the message's timestamp). The model reads its
  SUMMARY.
  """
  @spec reply(map()) :: Session.entry()
  def reply(attrs) do
    model = attrs[:model] || "storyboard"
    blocks = attrs[:blocks] || []

    {provider, model_id} =
      case model |> Session.to_pi_model() |> String.split("/", parts: 2) do
        ["unknown", id] -> {"bezalel", id}
        [provider, id] -> {provider, id}
      end

    display =
      %{
        "blocks" => blocks,
        "passage" => attrs[:passage],
        "card" => attrs[:card],
        "image" => attrs[:image],
        "model" => model
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    text = summary(blocks)

    %{
      "type" => "message",
      "message" => %{
        "role" => "assistant",
        "content" => if(text == "", do: [], else: [%{"type" => "text", "text" => text}]),
        "api" => "bezalel",
        "provider" => provider,
        "model" => model_id,
        "usage" => Session.usage(nil),
        "stopReason" => "stop",
        "timestamp" => timestamp(attrs[:at]),
        "bezalel" => display
      }
    }
  end

  defp timestamp(%DateTime{} = at), do: DateTime.to_unix(at, :millisecond)
  defp timestamp(_), do: System.os_time(:millisecond)

  # The SUMMARY's whole text (a cut header repeats it under the cut).
  defp summary(blocks) do
    Enum.find_value(blocks, "", fn
      %{"id" => "sum", "cut" => true, "rest" => rest} -> String.trim(rest)
      %{"id" => "sum"} = b -> String.trim("#{b["first"]} #{b["rest"]}")
      _ -> nil
    end)
  end

  @doc "A branch marker: an entry whose only job is to put the leaf under `parent`."
  @spec marker() :: Session.entry()
  def marker, do: %{"type" => "custom", "customType" => @marker, "data" => %{}}

  # ── Reading ──────────────────────────────────────────────────────────────

  @doc "The chat's messages on `branch`, in order. `session_id` scopes the image keys."
  @spec messages([Session.entry()], String.t()) :: [Message.t()]
  def messages(branch, session_id) do
    branch
    |> Enum.reduce([], &group/2)
    |> Enum.reverse()
    |> Enum.flat_map(fn
      {:user, entry} -> [user_message(entry, session_id)]
      {:consult, entry} -> [consult_message(entry)]
      {:agent, group, _closed?} -> reply_message(Enum.reverse(group), session_id)
    end)
  end

  # A reply runs from its first turn to the turn that ends it (one that
  # calls no tools) or a reply Bezalel wrote; the loop's notices go with
  # the reply before them. Two replies with no question between them (the
  # question was deleted) stay two.
  defp group(entry, groups) do
    case {kind(entry), groups} do
      {boundary, _} when boundary in [:user, :consult] ->
        [{boundary, entry} | groups]

      {:notice, [{:agent, group, closed?} | rest]} ->
        [{:agent, [entry | group], closed?} | rest]

      {:turn, [{:agent, group, false} | rest]} ->
        [{:agent, [entry | group], ends_reply?(entry)} | rest]

      {kind, _} when kind in [:turn, :notice] ->
        [{:agent, [entry], ends_reply?(entry)} | groups]

      {:skip, _} ->
        groups
    end
  end

  defp ends_reply?(%{"message" => %{"role" => "assistant"} = m}),
    do: m["stopReason"] != "toolUse" or Map.has_key?(m, "bezalel")

  defp ends_reply?(_entry), do: false

  defp kind(%{"type" => "message", "message" => %{"role" => "user"}}), do: :user

  defp kind(%{"type" => "message", "message" => %{"role" => role}})
       when role in ["assistant", "toolResult"],
       do: :turn

  defp kind(%{"type" => "custom_message"} = entry),
    do: if(Session.attribution(entry), do: :consult, else: :notice)

  defp kind(_entry), do: :skip

  defp user_message(%{"id" => id, "message" => m} = entry, session_id) do
    %Message{
      id: id,
      role: :user,
      text: Session.typed(m),
      images: images([entry], session_id),
      materials: materials([entry]),
      entries: [id]
    }
  end

  defp consult_message(%{"id" => id} = entry) do
    %{model: model, purpose: purpose} = Session.attribution(entry)
    text = Session.text(entry["content"])

    %Message{
      id: id,
      role: :consult,
      text: text,
      model: model,
      purpose: purpose,
      blocks: [Reply.consult_block("consult", %{model: model, purpose: purpose, text: text})],
      entries: [id]
    }
  end

  defp reply_message([first | _] = group, session_id) do
    message = %Message{
      id: first["id"],
      role: :agent,
      images: images(group, session_id),
      materials: materials(group),
      entries: Enum.map(group, & &1["id"]),
      usage: Bezalel.Usage.reply_usage(group)
    }

    message =
      case Enum.find_value(group, &get_in(&1, ["message", "bezalel"])) do
        %{} = shown ->
          %{
            message
            | blocks: shown["blocks"] || [],
              passage: shown["passage"],
              card: shown["card"],
              image: shown["image"],
              model: shown["model"]
          }

        nil ->
          reply = replay(group)

          %{
            message
            | blocks: Reply.blocks(reply),
              card: reply.card,
              citations: Reply.sources(reply),
              model: model(group),
              stop_reason: stop_reason(group)
          }
      end

    if shown?(message), do: [message], else: []
  end

  defp stop_reason(group) do
    Enum.find_value(Enum.reverse(group), fn
      %{"message" => %{"role" => "assistant"} = m} -> m["stopReason"]
      _ -> nil
    end)
  end

  defp shown?(m),
    do:
      m.blocks != [] or m.images != [] or m.materials != [] or
        (m.card || m.passage || m.image) != nil

  # The loop's events for a reply's entries, folded as they were live.
  defp replay(group) do
    group
    |> Enum.reduce({Reply.new(nil, nil), 0}, fn
      %{"message" => %{"role" => "assistant"} = m} = entry, {r, turn} ->
        turn = turn + 1

        r =
          r
          |> Reply.apply(%{type: :turn_start, turn: turn})
          |> delta(:thinking, Session.thinking(m))
          |> delta(:text, Session.text(m["content"]))
          |> Reply.apply(%{type: :message_end, entry: entry})

        r =
          Enum.reduce(Session.tool_calls(m), r, fn call, r ->
            Reply.apply(r, %{
              type: :tool_execution_start,
              id: call["id"],
              name: call["name"],
              arguments: call["arguments"]
            })
          end)

        {r, turn}

      %{"message" => %{"role" => "toolResult"} = m}, {r, turn} ->
        event = %{
          type: :tool_execution_end,
          id: m["toolCallId"],
          name: m["toolName"],
          text: Session.text(m["content"]),
          is_error: m["isError"] == true,
          details: nil,
          card: Details.kept_card(m["details"]),
          citations: Details.kept_citations(m["details"])
        }

        {Reply.apply(r, event), turn}

      # Notices (the loop's, an error's) aren't part of what the chat shows.
      _entry, acc ->
        acc
    end)
    |> elem(0)
    |> Reply.apply(%{type: :agent_end, reason: :done})
  end

  defp delta(r, _kind, ""), do: r
  defp delta(r, kind, text), do: Reply.apply(r, %{type: :message_update, kind: kind, delta: text})

  # The model of the reply's last turn, as a req_llm spec.
  defp model(group) do
    Enum.find_value(Enum.reverse(group), fn
      %{"message" => %{"role" => "assistant", "provider" => p, "model" => m}} ->
        Session.from_pi_model("#{p}/#{m}")

      _ ->
        nil
    end)
  end

  @doc """
  The image parts of `entries` (a picture from a tool, a model or an
  attachment), as `Bezalel.Library.Message` lists them.
  """
  @spec images([Session.entry()], String.t()) :: [Message.image()]
  def images(entries, session_id) do
    for %{"id" => id, "message" => %{"content" => content}} <- entries,
        is_list(content),
        {%{"type" => "image"} = part, index} <- Enum.with_index(content),
        do: %{
          key: "#{session_id}/#{id}/#{index}",
          entry: id,
          index: index,
          mime: part["mimeType"]
        }
  end

  @doc """
  The materials `entries` send or receive by reference (a user's
  attachment, a tool's picture: rho's attachments with a `"ref"`), as
  `Bezalel.Library.Message` lists them.
  """
  @spec materials([Session.entry()]) :: [Message.material()]
  def materials(entries) do
    for %{"message" => %{} = m} = entry <- entries,
        %{"ref" => ref} = a <- Session.attachments(m),
        is_binary(ref),
        do: %{
          id: ref,
          kind: Materials.kind(a["mimeType"] || ""),
          mime: a["mimeType"],
          name: a["name"] || ref,
          about: a["about"],
          entry: entry["id"]
        }
  end

  # ── Edits ────────────────────────────────────────────────────────────────

  @typedoc "A branch move: the entry to branch from, and the entries to copy onto it."
  @type move :: {parent :: String.t() | nil, copies :: [Session.entry()]}

  @doc """
  The move that deletes `ids` (entry ids) from `branch`: from the entry
  before the first of them, copying the rest. `:none` when none of them
  is on the branch.
  """
  @spec delete([Session.entry()], [String.t()]) :: move() | :none
  def delete(branch, ids) do
    gone = MapSet.new(ids)

    case Enum.split_while(branch, &(not MapSet.member?(gone, &1["id"]))) do
      {_kept, []} ->
        :none

      {kept, after_first} ->
        parent = kept |> List.last() |> then(&(&1 && &1["id"]))
        {parent, after_first |> Enum.reject(&MapSet.member?(gone, &1["id"])) |> copies()}
    end
  end

  @doc """
  The move that undoes a delete which took the leaf from `before` to
  `after`, on the current `branch`: back to `before`, with copies of what
  was added after `after`. `:gone` when `after` isn't on the branch any
  more (another edit moved it).
  """
  @spec undo([Session.entry()], String.t(), String.t() | nil) :: move() | :gone
  def undo(branch, before, after_id) do
    case Enum.split_while(branch, &(&1["id"] != after_id)) do
      {_, [_ | added]} -> {before, copies(added)}
      {_, []} when after_id == nil -> {before, copies(branch)}
      {_, []} -> :gone
    end
  end

  @doc """
  Plans taking the website's turns into the phone's copy of a conversation
  after both went on while apart. `base` is the entries the two copies had
  in common (the file up to the last offset both had); `phone_branch` and
  `server_branch` are each copy's active branch now (`Rho.Session.open/2`'s).

  Each branch starts with its part of the common conversation: entries of
  `base`, or copies of them (Delete and Undo copy entries without their
  `id`, `parentId` and `timestamp`, so a copy equals its original but for
  those); the rest are that side's own turns. The website's own turns are
  the server branch's minus what the phone already holds (by id, or as a
  copy). The common part is the website's when its branch moved off the
  last entry both had (a Delete or Undo there), else the phone's (which may
  have moved itself). The two sides' own turns follow it in the order they
  began (by their first entry's message time, which copies keep; a tie
  keeps the phone's first).

  The move branches from the last entry the phone's branch shares with
  that result and copies the rest of it (the phone's originals stay on an
  inactive branch), then a notice (`Rho.Session.custom/2`) saying how many
  messages came from the computer, when any did. Copies get new ids when
  appended (`Rho.Session.append/2`), so they never collide with the
  file's. `{:ok, move, count}` (`count` the website's new messages; 0 when
  the website only deleted or undid, with no notice), or `:none` when the
  website added nothing the phone lacks and left the common part as it
  was.
  """
  @spec merge([Session.entry()], [Session.entry()], [Session.entry()]) ::
          {:ok, move(), non_neg_integer()} | :none
  def merge(base, phone_branch, server_branch) do
    common? = held_in(base)
    {phone_common, phone_own} = Enum.split_while(phone_branch, common?)
    {server_common, server_own} = Enum.split_while(server_branch, common?)

    phone_has? = held_in(phone_branch)
    theirs = Enum.reject(server_own, &(&1["customType"] == @marker or phone_has?.(&1)))

    moved? = moved?(base, server_branch)
    count = length(messages(theirs, ""))
    common = if moved?, do: server_common, else: phone_common

    own =
      if began_later?(theirs, phone_own),
        do: phone_own ++ theirs,
        else: theirs ++ phone_own

    {parent, left, rest} = fork(phone_branch, common ++ own, nil)

    if count == 0 and (not moved? or (left == [] and rest == [])),
      do: :none,
      else: {:ok, {parent, copies(rest) ++ notice(count)}, count}
  end

  # Is an entry one of `entries`, or a copy of one? A copy keeps all of its
  # original but `id`, `parentId` and `timestamp` (`copies/1`).
  defp held_in(entries) do
    ids = MapSet.new(entries, & &1["id"])
    signatures = MapSet.new(entries, &signature/1)
    &(MapSet.member?(ids, &1["id"]) or MapSet.member?(signatures, signature(&1)))
  end

  defp signature(entry), do: Map.drop(entry, ["id", "parentId", "timestamp"])

  defp notice(0), do: []
  defp notice(count), do: [Session.custom(:notice, notice_text(count))]

  # Has the website's branch moved off the last entry both copies had?
  defp moved?(base, server_branch) do
    case base |> Enum.filter(&(is_binary(&1["id"]) and &1["type"] != "session")) |> List.last() do
      nil -> false
      %{"id" => leaf} -> not Enum.any?(server_branch, &(&1["id"] == leaf))
    end
  end

  # Where `branch` and `target` part: the last entry they share from the
  # start (nil for none), and what's left of each.
  defp fork([%{"id" => id} | branch], [%{"id" => id} | target], _parent),
    do: fork(branch, target, id)

  defp fork(branch, target, parent), do: {parent, branch, target}

  defp notice_text(1),
    do: "1 message from your computer was added while your phone was offline."

  defp notice_text(n),
    do: "#{n} messages from your computer were added while your phone was offline."

  # Did `theirs` begin after `ours`? With none of ours, they simply follow.
  defp began_later?(_theirs, []), do: true

  defp began_later?(theirs, ours) do
    case {Enum.find_value(theirs, &time/1), Enum.find_value(ours, &time/1)} do
      {t, o} when is_integer(t) and is_integer(o) -> t >= o
      _ -> true
    end
  end

  # When an entry was first written, in ms: its message's time (a copy
  # keeps it), else the entry's own.
  defp time(%{"message" => %{"timestamp" => ms}}) when is_integer(ms), do: ms

  defp time(%{"timestamp" => ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, at, _offset} -> DateTime.to_unix(at, :millisecond)
      _ -> nil
    end
  end

  defp time(_entry), do: nil

  @doc """
  The move that takes the last question off the branch, so it can be
  asked again: `{move, text}`, or `:none` when the branch doesn't end in a
  user message (another model's message is no question to ask again).
  """
  @spec take_question([Session.entry()]) :: {move(), String.t()} | :none
  def take_question(branch) do
    case last_user(branch) do
      {%{"message" => m} = entry, []} -> {{entry["parentId"], []}, Session.typed(m)}
      _ -> :none
    end
  end

  @doc """
  The move that drops a failed run's entries after the last user message,
  or after another model's message (a pushback's critique stays, its
  failed answer goes); `:none` when there are none.
  """
  @spec drop_after_question([Session.entry()]) :: move() | :none
  def drop_after_question(branch) do
    case last_user(branch) do
      {entry, [_ | _]} -> {entry["id"], []}
      _ -> :none
    end
  end

  # The last user message or other model's message, and what follows it
  # that the chat shows.
  defp last_user(branch) do
    case Enum.split_while(Enum.reverse(branch), &(kind(&1) not in [:user, :consult])) do
      {_after, []} -> nil
      {after_rev, [entry | _]} -> {entry, after_rev |> Enum.reverse() |> Enum.reject(&skip?/1)}
    end
  end

  defp skip?(entry), do: kind(entry) == :skip

  # Entries to append again on a new branch: without their ids (append
  # gives new ones), branch markers, or compactions (their summary may hold
  # a deleted message and their `firstKeptEntryId` names the old branch:
  # the next loop compacts again from what the branch really holds).
  defp copies(entries) do
    for entry <- entries,
        entry["customType"] != @marker,
        entry["type"] != "compaction",
        do: Map.drop(entry, ["id", "parentId", "timestamp"])
  end
end
