defmodule Bezalel.Library.Transcript do
  @moduledoc """
  A conversation's transcript is its rho session (`Rho.Session`, pi's
  JSONL): this module reads the chat's messages off a branch of it and
  plans the branch edits behind Delete and Undo. No file I/O; the host app does
  the reading and writing.

  **Messages.** On the active branch, each user `message` entry is a user
  message; the entries between two of them (the model's turns, tool
  results, the loop's notices) are one reply (`Bezalel.Library.Message`).
  A live reply's blocks are rebuilt from its entries by the fold that drew
  it while it streamed (`Bezalel.Agent.Reply`): each turn's thinking, each
  tool call with its result, the answer as the SUMMARY; its passage card
  comes from the tool result's kept `details` (the host app's agent loop
  keeps the card there). A reply Bezalel wrote itself (the storyboard's, or one
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
  """

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
      {:agent, group, _closed?} -> reply_message(Enum.reverse(group), session_id)
    end)
  end

  # A reply runs from its first turn to the turn that ends it (one that
  # calls no tools) or a reply Bezalel wrote; the loop's notices go with
  # the reply before them. Two replies with no question between them (the
  # question was deleted) stay two.
  defp group(entry, groups) do
    case {kind(entry), groups} do
      {:user, _} ->
        [{:user, entry} | groups]

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

  defp kind(%{"type" => "custom_message"}), do: :notice
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

  defp reply_message([first | _] = group, session_id) do
    message = %Message{
      id: first["id"],
      role: :agent,
      images: images(group, session_id),
      materials: materials(group),
      entries: Enum.map(group, & &1["id"])
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
          %{message | blocks: Reply.blocks(reply), card: reply.card, model: model(group)}
      end

    if shown?(message), do: [message], else: []
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
          card: m["details"]
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
  The move that takes the last question off the branch, so it can be
  asked again: `{move, text}`, or `:none` when the branch doesn't end in a
  user message.
  """
  @spec take_question([Session.entry()]) :: {move(), String.t()} | :none
  def take_question(branch) do
    case last_user(branch) do
      {%{"message" => m} = entry, []} -> {{entry["parentId"], []}, Session.typed(m)}
      _ -> :none
    end
  end

  @doc """
  The move that drops a failed run's entries after the last user message
  (the reply is shown as its error, then asked again); `:none` when there
  are none.
  """
  @spec drop_after_question([Session.entry()]) :: move() | :none
  def drop_after_question(branch) do
    case last_user(branch) do
      {entry, [_ | _]} -> {entry["id"], []}
      _ -> :none
    end
  end

  # The last user message and what follows it that the chat shows.
  defp last_user(branch) do
    case Enum.split_while(Enum.reverse(branch), &(kind(&1) != :user)) do
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
