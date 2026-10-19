defmodule Bezalel.Agent.TitleTest do
  use ExUnit.Case, async: true

  alias Bezalel.Agent.Title
  alias Bezalel.Library.Message
  alias Bezalel.Test.FakeLLM

  @lead "anthropic:claude-opus-4-1"

  defp question(text, materials \\ []),
    do: %Message{
      id: "q#{System.unique_integer([:positive])}",
      role: :user,
      text: text,
      materials: materials
    }

  defp reply(summary),
    do: %Message{
      id: "r#{System.unique_integer([:positive])}",
      role: :agent,
      blocks: [
        %{"id" => "t1", "type" => "THINKING", "first" => "secret thoughts", "rest" => ""},
        %{"id" => "sum", "type" => "SUMMARY", "first" => summary, "rest" => ""}
      ]
    }

  defp conversation do
    [
      question("Who was Bezalel?"),
      reply(
        "Bezalel, son of Uri, was filled with the Spirit to build the tabernacle (Ex 31:1-5)."
      )
    ]
  end

  defp run(script, messages, current \\ nil) do
    {:ok, llm} = FakeLLM.start(script)
    result = Title.run(@lead, messages, current, consult: [llm: {FakeLLM, llm}])
    {result, FakeLLM.requests(llm)}
  end

  defp prompt_text(%{messages: [message | _]}) do
    message.content |> Enum.map_join(& &1.text)
  end

  describe "model/1" do
    test "is the small model of the lead's provider" do
      assert Title.model(@lead) =~ ~r/^anthropic:claude-haiku/
      assert Title.model("openai:gpt-5.5") =~ ~r/^openai:.*-mini/
      assert Title.model("google:gemini-3.1-pro-preview") =~ ~r/^google:.*flash-lite/
      refute Title.model("google:gemini-3.1-pro-preview") =~ "image"
      assert Title.model("openai_codex:gpt-6-sol") =~ ~r/^openai_codex:.*luna/
    end

    test "is the lead itself for a provider rho doesn't know" do
      assert Title.model("mistral:large") == "mistral:large"
    end
  end

  describe "run/4" do
    test "asks the small model with the conversation and returns its title and summary" do
      haiku = Title.model(@lead)

      answer =
        "Title: Bezalel, the Spirit-filled craftsman\n" <>
          "Summary: Who Bezalel was and why Exodus 31 says he was filled with the Spirit."

      {result, [request]} = run(%{haiku => [[{:text, answer}]]}, conversation())

      assert result ==
               {:ok,
                %{
                  title: "Bezalel, the Spirit-filled craftsman",
                  summary: "Who Bezalel was and why Exodus 31 says he was filled with the Spirit."
                }}

      assert request.model == haiku
      assert request.system_prompt == Title.system()
      text = prompt_text(request)
      assert text =~ "User: Who was Bezalel?"
      assert text =~ "Assistant: Bezalel, son of Uri"
      refute text =~ "secret thoughts"
      refute text =~ "Current title"
    end

    test "sends the current title and summary to refine once it has a summary" do
      haiku = Title.model(@lead)

      answer =
        ~s({"title": "Oholiab and Bezalel", "summary": "The two craftsmen of the tabernacle."})

      messages = conversation() ++ [question("And Oholiab?"), reply("Oholiab of Dan helped him.")]
      current = %{title: "Bezalel the craftsman", summary: "Who Bezalel was."}

      {{:ok, %{title: "Oholiab and Bezalel"}}, [request]} =
        run(%{haiku => [[{:text, answer}]]}, messages, current)

      assert prompt_text(request) =~
               "Current title: Bezalel the craftsman\nCurrent summary: Who Bezalel was."
    end

    test "a placeholder title (no summary yet) isn't sent as one to keep" do
      haiku = Title.model(@lead)

      {{:ok, _}, [request]} =
        run(
          %{haiku => [[{:text, "Title: Bezalel\nSummary: x"}]]},
          conversation(),
          %{title: "New study", summary: nil}
        )

      refute prompt_text(request) =~ "New study"
    end

    test "a failed call or an answer without a title is an error (the host keeps the old title)" do
      haiku = Title.model(@lead)

      assert {{:error, {:other, "down"}}, _} =
               run(%{haiku => [[{:error, {:other, "down"}}]]}, conversation())

      assert {{:error, {:unreadable, "I can't help with that, I'm afraid, as it is not clear."}},
              _} =
               run(
                 %{
                   haiku => [[{:text, "I can't help with that, I'm afraid, as it is not clear."}]]
                 },
                 conversation()
               )
    end

    test "a reply from the storyboard (no model rho calls) isn't named" do
      assert {{:error, :no_model}, []} =
               run(%{}, conversation())
               |> then(fn _ -> {Title.run("storyboard", conversation()), []} end)
    end

    test "takes only the host's consult options, and keeps its own" do
      haiku = Title.model(@lead)
      {:ok, llm} = FakeLLM.start(%{haiku => [[{:text, "Title: Bezalel\nSummary: Who he was."}]]})

      assert {:ok, %{title: "Bezalel"}} =
               Title.run(@lead, conversation(), nil,
                 consult: [
                   llm: {FakeLLM, llm},
                   max_tokens: 10,
                   loop: self(),
                   purpose: "x",
                   budget: nil,
                   budget: nil
                 ]
               )

      assert [%{max_tokens: 1_024, system_prompt: system}] = FakeLLM.requests(llm)
      assert system == Title.system()
    end

    test "nothing to name before the first question" do
      assert {{:error, :empty}, []} = run(%{}, [])
      assert {{:error, :empty}, []} = run(%{}, [reply("A storyboard reply.")])
    end
  end

  describe "parse/1" do
    test "reads a fenced JSON object and tidies it" do
      answer = """
      ```json
      {"title": "**\\"Ruach in Genesis 1:2.\\"**", "summary": "  What   ruach means\\n in Genesis 1:2. "}
      ```
      """

      assert Title.parse(answer) ==
               {:ok,
                %{title: "Ruach in Genesis 1:2", summary: "What ruach means in Genesis 1:2."}}
    end

    test "reads Title: and Summary: lines, in Markdown or not" do
      assert Title.parse("Title: The tabernacle's lampstand\nSummary: The menorah in Exodus 25.") ==
               {:ok, %{title: "The tabernacle's lampstand", summary: "The menorah in Exodus 25."}}

      assert Title.parse("**Title:** \"Ruach in Genesis 1:2.\"\n\n**summary:** What ruach means.") ==
               {:ok, %{title: "Ruach in Genesis 1:2", summary: "What ruach means."}}
    end

    test "cuts a long title to eight words and a long summary at a word" do
      long = Enum.map_join(1..12, " ", &"word#{&1}")
      summary = String.duplicate("covering ", 40)

      {:ok, %{title: title, summary: cut}} =
        Title.parse(Jason.encode!(%{"title" => long, "summary" => summary}))

      assert title == Enum.map_join(1..8, " ", &"word#{&1}")
      assert String.length(cut) <= 200
      assert String.ends_with?(cut, "covering…")
    end

    test "reads labelled lines in a list" do
      assert Title.parse("- Title: Ruach\n- Summary: Wind and spirit.") ==
               {:ok, %{title: "Ruach", summary: "Wind and spirit."}}

      assert Title.parse("1. **Title:** Ruach\n2. **Summary:** Wind and spirit.") ==
               {:ok, %{title: "Ruach", summary: "Wind and spirit."}}
    end

    test "a refusal or a half answer is unreadable (the old name and summary stay)" do
      for answer <- [
            "",
            "I cannot do that",
            "Summary: A short summary.",
            "Title:\nSummary: A short summary.",
            "Title: Ruach\nSummary:",
            ~s({"title": "", "summary": "x"}),
            ~s({"title": "Ruach"}),
            "Ruach\nWind.\nAnd more.",
            "I cannot comply\nPlease ask something else.",
            "Deuteronomy 32:8 variant readings\nCompares the Scrolls and the Septuagint.",
            "- Title:\n- Summary: A short summary."
          ],
          do: assert(Title.parse(answer) == {:error, :unreadable}, inspect(answer))
    end
  end

  describe "from_question/1" do
    test "is the question's first line, cut at a word" do
      assert Title.from_question("Who was Bezalel?\nAnd Oholiab?") == "Who was Bezalel?"

      assert Title.from_question(
               "What do the Dead Sea Scrolls read at Deuteronomy 32:8, compared with the Masoretic Text?"
             ) == "What do the Dead Sea Scrolls read at Deuteronomy 32:8…"

      assert Title.from_question("  ") == nil
      assert Title.from_question(nil) == nil
    end
  end

  describe "transcript/1" do
    test "keeps the first question and the newest messages when it's long" do
      filler = String.duplicate("a", 1_400)

      middle =
        for n <- 1..20,
            m <- [question("question #{n} #{filler}"), reply("answer #{n} #{filler}")],
            do: m

      text = Title.transcript([question("The very first question") | middle])

      assert String.starts_with?(text, "User: The very first question")
      assert text =~ "[…earlier messages left out…]"
      assert text =~ "answer 20"
      refute text =~ "question 1 "
      assert String.length(text) <= 12_000
    end

    test "starts at the first question (a reply left before it by a delete goes)" do
      text =
        Title.transcript([
          reply("An orphan reply."),
          question("Who was Oholiab?"),
          reply("Bezalel's partner.")
        ])

      assert text == "User: Who was Oholiab?\n\nAssistant: Bezalel's partner."
    end

    test "names an attachment sent without words" do
      m = question("", [%{id: "m1", kind: :image, mime: "image/jpeg", name: "menorah.jpg"}])
      assert Title.transcript([m]) == "User: [attached: menorah.jpg]"
    end
  end
end
