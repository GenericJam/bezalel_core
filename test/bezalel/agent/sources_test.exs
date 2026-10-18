defmodule Bezalel.Agent.SourcesTest do
  # A reply's sources: the citations its tools returned, kept in the session
  # with the card (Bezalel.Agent.keep_details/2), folded live and on replay,
  # each marked cited when the answer links it.
  use ExUnit.Case, async: true

  alias Bezalel.Agent
  alias Bezalel.Agent.{Card, Reply}
  alias Bezalel.Library.Transcript
  alias Bezalel.Study.{Citation, Citations}
  alias Rho.Session

  @net %{key: "net", abbreviation: "NET", url: "http://netbible.org"}

  defp lookup_details do
    verse = %{
      reference: "Jhn.3.16",
      chapter: 3,
      verse: 16,
      english: "For this is the way God loved the world",
      words: [],
      translated: true
    }

    %{
      label: "John 3:16",
      reference: "Jhn.3.16",
      verses: [verse],
      translation: @net,
      citations: [Citations.net("Jhn.3.16"), Citations.step("Jhn.3.16")]
    }
  end

  defp search_details do
    %{
      citations: [
        Citations.ancient("antiquities", "Antiquities 18.63–64"),
        Citations.net("Jhn.3.16")
      ]
    }
  end

  describe "keep_details/2" do
    test "keeps the card and the citations, JSON-safe" do
      kept = Agent.keep_details("lookup_verse", lookup_details())
      assert kept["card"]["version_url"] == "https://netbible.org/bible/John+3:16"
      assert Enum.map(kept["citations"], & &1["work"]) == ["net", "step"]
      assert kept == kept |> Jason.encode!() |> Jason.decode!()
    end

    test "a tool with no card keeps its citations; nothing to keep is nil" do
      assert %{"citations" => [_, _]} =
               kept = Agent.keep_details("search_ancient_sources", search_details())

      refute Map.has_key?(kept, "card")
      assert Agent.keep_details("parse_morphology", %{citations: []}) == nil
      assert Agent.keep_details("anything", nil) == nil
    end

    test "reads the old shape (a bare card) as a card with no citations" do
      card = Agent.keep_details("lookup_verse", lookup_details())["card"]
      assert Agent.kept_card(card) == card
      assert Agent.kept_citations(card) == []
    end
  end

  defp live_reply(answer) do
    Reply.new(1, "m")
    |> Reply.apply(%{type: :tool_execution_start, id: "1", name: "lookup_verse", arguments: %{}})
    |> Reply.apply(%{
      type: :tool_execution_end,
      id: "1",
      name: "lookup_verse",
      text: "…",
      is_error: false,
      details: lookup_details()
    })
    |> Reply.apply(%{
      type: :tool_execution_start,
      id: "2",
      name: "search_ancient_sources",
      arguments: %{}
    })
    |> Reply.apply(%{
      type: :tool_execution_end,
      id: "2",
      name: "search_ancient_sources",
      text: "…",
      is_error: false,
      details: search_details()
    })
    |> Reply.apply(%{type: :message_update, kind: :text, delta: answer})
    |> Reply.apply(%{type: :agent_end, reason: :done})
  end

  @answer "God loved the world ([NET](https://netbible.org/bible/John+3:16))."

  test "live: every tool's citations, once each, marked cited when the answer links them" do
    reply = live_reply(@answer)

    assert [{"net", true}, {"step", false}, {"josephus", false}] ==
             Enum.map(Reply.sources(reply), &{&1.work, &1.cited})
  end

  test "an errored tool result contributes no citations" do
    reply =
      Reply.new(1, "m")
      |> Reply.apply(%{
        type: :tool_execution_end,
        id: "1",
        name: "lookup_verse",
        text: "Error",
        is_error: true,
        details: lookup_details()
      })

    assert reply.citations == []
  end

  defp entries(details_for) do
    calls = [
      %{"id" => "c1", "name" => "lookup_verse", "arguments" => %{"reference" => "John 3:16"}},
      %{"id" => "c2", "name" => "search_ancient_sources", "arguments" => %{"query" => "Jesus"}}
    ]

    [
      Session.user("Who loved the world?") |> Map.put("id", "u1"),
      %{tool_calls: calls, stop_reason: "toolUse"}
      |> Session.assistant("anthropic:m")
      |> Map.put("id", "a1"),
      "c1"
      |> Session.tool_result("lookup_verse", "…", false,
        details: details_for.("lookup_verse", lookup_details())
      )
      |> Map.put("id", "t1"),
      "c2"
      |> Session.tool_result("search_ancient_sources", "…", false,
        details: details_for.("search_ancient_sources", search_details())
      )
      |> Map.put("id", "t2"),
      %{text: @answer, stop_reason: "stop"}
      |> Session.assistant("anthropic:m")
      |> Map.put("id", "a2")
    ]
  end

  test "replayed from the session: the card and the marked citations, as live" do
    stored = entries(&Agent.keep_details/2) |> Jason.encode!() |> Jason.decode!()
    [_question, message] = Transcript.messages(stored, "s")

    assert message.card["title"] == "John 3:16"

    assert Enum.map(message.citations, &{&1.work, &1.cited}) ==
             Enum.map(Reply.sources(live_reply(@answer)), &{&1.work, &1.cited})

    assert [%Citation{url: "https://netbible.org/bible/John+3:16", cited: true} | _] =
             message.citations
  end

  test "a session from before citations (the bare card kept) still shows its card" do
    stored = entries(&Card.from_tool/2) |> Jason.encode!() |> Jason.decode!()
    [_question, message] = Transcript.messages(stored, "s")

    assert message.card["title"] == "John 3:16"
    assert message.citations == []
  end
end
