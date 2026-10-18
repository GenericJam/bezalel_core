defmodule Bezalel.Library.TranscriptMaterialsTest do
  use ExUnit.Case, async: true

  alias Bezalel.Agent.Reply
  alias Bezalel.Library.Transcript
  alias Rho.Session

  @photo String.duplicate("a", 64)
  @video String.duplicate("b", 64)
  @drawing String.duplicate("c", 64)

  defp with_id(entry, id), do: Map.put(entry, "id", id)

  defp question do
    attachments = [
      %{
        kind: :image,
        ref: @photo,
        name: "IMG_0412.jpg",
        mime: "image/jpeg",
        about: "image · 1.2 MB"
      },
      %{
        kind: :text,
        ref: @video,
        name: "Sermon.mov",
        mime: "video/quicktime",
        about: "video · 2:31",
        text: "In the beginning"
      }
    ]

    "Draw this lampstand" |> Transcript.user(attachments: attachments) |> with_id("u1")
  end

  defp drawing_reply do
    call = %{
      "id" => "call_1",
      "name" => "draw_image",
      "arguments" => %{"prompt" => "a lampstand"}
    }

    image = %{ref: @drawing, mime: "image/jpeg", name: "Drawing – a lampstand.jpg"}

    [
      %{tool_calls: [call], stop_reason: "toolUse"}
      |> Session.assistant("anthropic:claude-sonnet-4-5")
      |> with_id("a1"),
      "call_1"
      |> Session.tool_result("draw_image", "Drew the picture (ref #{@drawing}).", false,
        images: [image]
      )
      |> with_id("t1"),
      %{text: "Here is the lampstand.", stop_reason: "stop"}
      |> Session.assistant("anthropic:claude-sonnet-4-5")
      |> with_id("a2")
    ]
  end

  test "a user message lists the materials it sent by reference, with their kinds" do
    [message] = Transcript.messages([question()], "s1")

    assert message.text == "Draw this lampstand"
    assert message.images == []

    assert message.materials == [
             %{
               id: @photo,
               kind: :image,
               mime: "image/jpeg",
               name: "IMG_0412.jpg",
               about: "image · 1.2 MB",
               entry: "u1"
             },
             %{
               id: @video,
               kind: :video,
               mime: "video/quicktime",
               name: "Sermon.mov",
               about: "video · 2:31",
               entry: "u1"
             }
           ]
  end

  test "a reply lists a tool's picture by reference" do
    [_question, reply] = Transcript.messages([question() | drawing_reply()], "s1")

    assert [%{id: @drawing, kind: :image, name: "Drawing – a lampstand.jpg", entry: "t1"}] =
             reply.materials

    assert reply.images == []
  end

  test "pictures stored inline, as before materials, are still images" do
    call = %{"id" => "call_1", "name" => "screenshot", "arguments" => %{}}

    entries = [
      "Show me" |> Transcript.user() |> with_id("u1"),
      %{tool_calls: [call], stop_reason: "toolUse"}
      |> Session.assistant("openai:gpt-5")
      |> with_id("a1"),
      "call_1"
      |> Session.tool_result("screenshot", "the screen", false, images: [{"image/png", "png"}])
      |> with_id("t1"),
      %{text: "Done.", stop_reason: "stop"} |> Session.assistant("openai:gpt-5") |> with_id("a2")
    ]

    [_question, reply] = Transcript.messages(entries, "s1")
    assert reply.images == [%{key: "s1/t1/1", entry: "t1", index: 1, mime: "image/png"}]
    assert reply.materials == []
  end

  test "a reply that is only a picture by reference still shows" do
    [_call, result, _answer] = drawing_reply()

    reply =
      Reply.new(1, "anthropic:claude-sonnet-4-5", "s1")
      |> Reply.apply(%{type: :message_end, entry: result})

    assert [%{id: @drawing, kind: :image, entry: "t1"}] = reply.materials
    assert Reply.any?(reply)
  end
end
