defmodule Bezalel.Library.TranscriptConsultTest do
  # Another model in the chat: a pushback's critique as its own message,
  # and a model the lead asks itself (rho's ask_model) as a CONSULT block.
  use ExUnit.Case, async: true

  alias Bezalel.Agent.Reply
  alias Bezalel.Library.{Message, Transcript}
  alias Rho.Session

  @lead "anthropic:claude-sonnet-4-5"
  @critic "google:gemini-3.1-pro-preview"

  defp with_id(entry, id), do: Map.put(entry, "id", id)

  defp answer(text, id, stop \\ "stop"),
    do: %{text: text, stop_reason: stop} |> Session.assistant(@lead) |> with_id(id)

  defp ask_model_turn do
    call = %{
      "id" => "call_1",
      "name" => "ask_model",
      "arguments" => %{
        "model" => @critic,
        "purpose" => "critique",
        "prompt" => "Check my reading.",
        "include_conversation" => true
      }
    }

    [
      %{tool_calls: [call], stop_reason: "toolUse"} |> Session.assistant(@lead) |> with_id("a1"),
      "call_1"
      |> Session.tool_result(
        "ask_model",
        "#{@critic} (critique):\n\n1. **minor** Cite BDB.",
        false
      )
      |> with_id("t1"),
      answer("Gemini is right: BDB has it.", "a2")
    ]
  end

  test "a model the lead asks itself is a CONSULT block with its model and purpose" do
    branch = [Transcript.user("Have Gemini push back") |> with_id("u1") | ask_model_turn()]

    assert [%Message{role: :user}, %Message{role: :agent, blocks: [consult, summary]}] =
             Transcript.messages(branch, "s")

    assert consult["type"] == "CONSULT"
    assert {consult["model"], consult["purpose"]} == {@critic, "critique"}
    assert consult["text"] == "1. **minor** Cite BDB."
    assert summary["text"] == "Gemini is right: BDB has it."
  end

  test "live, the consulted model's words stream into its block" do
    args = %{"model" => @critic, "purpose" => "second_opinion", "prompt" => "?"}

    r =
      Reply.new(1, @lead)
      |> Reply.apply(%{type: :tool_execution_start, id: "c1", name: "ask_model", arguments: args})
      |> Reply.apply(%{
        type: :consult_start,
        id: "k1",
        model: @critic,
        purpose: "second_opinion",
        call_id: "c1"
      })

    assert [%{"type" => "CONSULT", "first" => "Running…"}] = Reply.blocks(r)

    r =
      Reply.apply(r, %{
        type: :consult_delta,
        id: "k1",
        model: @critic,
        purpose: "second_opinion",
        call_id: "c1",
        kind: :text,
        delta: "Another reading: wind."
      })

    assert [%{"type" => "CONSULT", "text" => "Another reading: wind."}] = Reply.blocks(r)

    # A failed call is a TOOL CALL with its error, as any tool's.
    r =
      Reply.apply(r, %{
        type: :tool_execution_end,
        id: "c1",
        name: "ask_model",
        text: "Gemini (Google) isn't signed in",
        is_error: true
      })

    assert [%{"type" => "TOOL CALL", "rest" => "Error: Gemini (Google) isn't signed in"}] =
             Reply.blocks(r)
  end

  test "a critique ends the reply before it; Ask again and Delete keep to their own message" do
    critique =
      "1. **major** Overreach." |> Session.model_message(@critic, "critique") |> with_id("k1")

    question = Transcript.user("What does ruach mean?") |> with_id("u1")
    response = answer("Fair.", "a2")
    branch = [question, answer("Spirit.", "a1"), critique, response]

    assert [
             %Message{role: :user},
             %Message{role: :agent, entries: ["a1"]},
             %Message{role: :consult, id: "k1", entries: ["k1"], model: @critic} = c,
             %Message{role: :agent, entries: ["a2"]}
           ] = Transcript.messages(branch, "s")

    assert {c.purpose, c.text} == {"critique", "1. **major** Overreach."}

    # The lead's answer to it failed: that answer goes, the critique stays;
    # there's no question after the critique to ask again.
    failed = [question, answer("Spirit.", "a1"), critique, answer("", "a2", "error")]
    assert Transcript.drop_after_question(failed) == {"k1", []}
    assert Transcript.take_question(failed) == :none
    assert Transcript.take_question([question, answer("Spirit.", "a1"), critique]) == :none

    # Deleting the critique takes only its entry.
    assert Transcript.delete(branch, c.entries) ==
             {"a1", [Map.drop(response, ["id", "parentId", "timestamp"])]}
  end
end
