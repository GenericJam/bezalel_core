defmodule Bezalel.Agent.PushbackTest do
  # async: false: the sign-ins (`config :rho, :credential_store`), rho's
  # consult system prompt and attachment resolver are app-wide.
  use ExUnit.Case, async: false

  alias Bezalel.Agent.{Pushback, Reply}
  alias Bezalel.Library.{Message, Transcript}
  alias Bezalel.Materials
  alias Bezalel.Test.{CredentialStore, FakeLLM, MaterialStore}
  alias Rho.{Loop, Session}

  @moduletag :tmp_dir
  @moduletag :capture_log

  @lead "anthropic:claude-haiku-4-5"
  @critic "google:gemini-3.1-pro-preview"

  defmodule Lexicon do
    @moduledoc "Stands in for a study tool: a lexicon entry with its Source line."
    @behaviour Rho.Tool

    def name, do: "word_study"
    def description, do: "A lexicon entry."

    def parameter_schema,
      do: %{"type" => "object", "properties" => %{"word" => %{"type" => "string"}}}

    def run(_args, _ctx),
      do:
        {:ok,
         "H7307 rûaḥ: wind, breath, spirit.\nSource: [BDB H7307](https://example.org/bdb/H7307)"}
  end

  @question "What does ruach mean in Genesis 1:2?"
  @answer "In Genesis 1:2 ruach means only the Spirit of God."
  @critique "1. **major** \"means only the Spirit\": BDB gives wind and breath too (H7307)."
  @response "Fair: BDB gives wind, breath and spirit, and \"a mighty wind\" is a live reading."

  defp lead_script do
    [
      [{:tool_call, "c1", "word_study", %{"word" => "ruach"}}],
      [{:text, @answer}],
      [{:text, @response}]
    ]
  end

  defp start(dir, scripts, tools \\ [Lexicon]) do
    {:ok, llm} = FakeLLM.start(scripts)
    sup = start_supervised!(Task.Supervisor, id: make_ref())

    loop =
      start_supervised!(
        {Loop,
         session: Session.new(dir, @lead, dir),
         entries: [],
         llm: {FakeLLM, llm},
         tools: tools,
         task_supervisor: sup,
         data_dir: dir,
         system_prompt: "study",
         retry_base_ms: 1},
        id: make_ref()
      )

    :ok = Loop.subscribe(loop)
    %{loop: loop, llm: llm, sup: sup}
  end

  defp put_env(app, key, value) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(app, key, v)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  # The loop's events folded into `reply` until `stop?` says so: by
  # default the run's end, or a pushback that ended without one.
  defp fold(reply, stop? \\ &ended?/1, timeout \\ 2_000) do
    receive do
      {:rho, _sid, event} ->
        reply = Reply.apply(reply, event)
        if stop?.(event), do: reply, else: fold(reply, stop?, timeout)
    after
      timeout -> flunk("no end; reply so far: #{inspect(reply)}")
    end
  end

  defp ended?(%{type: :agent_end}), do: true
  defp ended?(%{type: :consult_end, call_id: nil, status: status}), do: status != :ok
  defp ended?(_event), do: false

  defp ask(loop, attachments \\ []) do
    :ok = Loop.prompt(loop, @question, attachments)
    fold(Reply.new(1, @lead))
  end

  defp pushback, do: Reply.pushback(1, @lead, @critic)

  defp branch(loop), do: Loop.snapshot(loop).entries
  defp messages(loop), do: Transcript.messages(branch(loop), "s")
  defp summary(%Message{blocks: blocks}), do: Enum.find(blocks, &(&1["id"] == "sum"))["text"]

  test "auto: after a finished reply the critic reviews it, then the lead answers the critique",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    %{loop: loop, llm: llm, sup: sup} =
      start(dir, %{@lead => lead_script(), @critic => [[{:text, @critique}]]})

    first = ask(loop)
    assert first.status == :done
    assert {:ok, task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)
    ref = Process.monitor(task)

    # A pushback is a reply of its own; the critique leads it, streaming.
    streaming = fold(pushback(), &(&1.type == :consult_delta))
    assert [%{"type" => "CONSULT", "text" => @critique}] = Reply.blocks(streaming)
    assert streaming.consult.status == :running

    reply = fold(streaming)
    assert reply.status == :done
    assert_receive {:DOWN, ^ref, :process, _, :normal}

    assert [consult | rest] = Reply.blocks(reply)
    assert consult["type"] == "CONSULT"

    assert {consult["model"], consult["purpose"], consult["text"]} ==
             {@critic, "critique", @critique}

    assert List.last(rest)["text"] == @response
    assert reply.consult.entry in reply.seen

    # The critic got the study brief, the question, the tool result with
    # its Source line, and the answer.
    [_, _, critic_request, response_request] = FakeLLM.requests(llm)
    assert critic_request.model == @critic
    assert critic_request.system_prompt == Pushback.critic_prompt()
    brief = text_of(List.last(critic_request.messages))
    assert brief =~ @question
    assert brief =~ "### word_study({\"word\":\"ruach\"})"
    assert brief =~ "Source: [BDB H7307](https://example.org/bdb/H7307)"
    assert brief =~ @answer

    # The lead got the critique as the critic's message, with the instruction.
    sent = text_of(List.last(response_request.messages))
    assert sent =~ ~s(model="#{@critic}" purpose="critique")
    assert sent =~ @critique
    assert sent =~ Pushback.instruction()

    # Stored: the question, the answer, the critique as the critic's own
    # message, then the lead's answer to it.
    assert [
             %Message{role: :user},
             %Message{role: :agent} = answer,
             %Message{role: :consult, model: @critic, purpose: "critique", text: @critique} = c,
             %Message{role: :agent} = response
           ] = messages(loop)

    assert [%{"type" => "CONSULT", "model" => @critic}] = c.blocks
    assert c.id == reply.consult.entry
    assert summary(response) == @response

    # One round: not on the answer again, not on the lead's response.
    shown = messages(loop)
    refute Pushback.offered?(shown, answer)
    refute Pushback.offered?(shown, response)
    assert Pushback.auto(loop, reply, @critic, task_supervisor: sup) == :skip

    assert {:error, "This answer has had its pushback" <> _} =
             Pushback.start(loop, @critic, task_supervisor: sup)

    # The consult's cost is the session's.
    assert Enum.any?(branch(loop), &(&1["customType"] == "rho.consult"))
  end

  test "the button: offered on the last finished reply, and pushes back on demand",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    %{loop: loop, sup: sup} =
      start(dir, %{@lead => lead_script(), @critic => [[{:text, @critique}]]})

    assert {:error, "There's no finished answer" <> _} =
             Pushback.start(loop, @critic, task_supervisor: sup)

    ask(loop)
    [question, answer] = messages(loop)
    assert Pushback.offered?([question, answer], answer)
    refute Pushback.offered?([question, answer], question)
    refute Pushback.offered?([question, answer, question], answer)

    assert {:ok, _task} = Pushback.start(loop, @critic, task_supervisor: sup)
    assert fold(pushback()).status == :done
    assert [_, _, %Message{role: :consult}, %Message{role: :agent}] = messages(loop)
  end

  test "no button and no pushback on a reply that was stopped, failed or written by Bezalel" do
    question = Transcript.user(@question) |> Map.put("id", "u1")

    for stop <- ["aborted", "error"] do
      turn = %{text: "Half an ans", stop_reason: stop} |> Session.assistant(@lead)
      branch = [question, Map.put(turn, "id", "a1")]
      [_, reply] = shown = Transcript.messages(branch, "s")

      refute Pushback.offered?(shown, reply)
      assert Pushback.target(branch) == {:error, :no_reply}
    end

    scripted = Transcript.reply(%{blocks: [%{"id" => "sum", "first" => "Hi.", "rest" => ""}]})
    branch = [question, Map.put(scripted, "id", "b1")]
    [_, reply] = shown = Transcript.messages(branch, "s")
    refute Pushback.offered?(shown, reply)
    assert Pushback.target(branch) == {:error, :no_reply}
  end

  test "no critic, or the critic's provider not signed in: a clear message, nothing sent",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic])
    %{loop: loop, llm: llm, sup: sup} = start(dir, %{@lead => lead_script()})
    first = ask(loop)

    assert {:error, why} = Pushback.start(loop, @critic, task_supervisor: sup)
    assert why =~ "can't push back"
    assert why =~ "Gemini (Google) isn't signed in"

    assert Pushback.auto(loop, first, nil) == :skip

    assert {:error, "Choose a model to push back in Settings (Pushback from)."} =
             Pushback.start(loop, nil)

    assert Enum.all?(FakeLLM.requests(llm), &(&1.model == @lead))
    assert [_, %Message{role: :agent}] = messages(loop)
  end

  test "a critic that fails ends the pushback with its error, as no failed run: the answer stays",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    %{loop: loop, llm: llm, sup: sup} =
      start(dir, %{@lead => lead_script(), @critic => [[{:error, {:other, "quota gone"}}]]})

    first = ask(loop)
    assert {:ok, _task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)

    reply = fold(pushback())
    assert {reply.status, reply.reason, reply.consult.status} == {:done, :consult_failed, :error}
    assert reply.error =~ "quota gone"

    refute_receive {:rho, _, %{type: :agent_start}}, 100
    assert [%{model: @lead}, %{model: @lead}, %{model: @critic}] = FakeLLM.requests(llm)
    assert [_, %Message{role: :agent} = answer] = shown = messages(loop)

    # Nothing used the round: the button is still there.
    assert Pushback.offered?(shown, answer)
  end

  test "a critique that comes back after the user moved on is not added, nor drawn in their reply",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    scripts = %{
      @lead => [[{:text, @answer}], [{:text, "Second answer."}]],
      @critic => [[{:sleep, 300}, {:text, @critique}]]
    }

    %{loop: loop, llm: llm, sup: sup} = start(dir, scripts)
    first = ask(loop)
    assert {:ok, task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)
    ref = Process.monitor(task)

    # The user asks again while the critic works: their reply knows
    # nothing of the critique.
    assert_receive {:rho, _, %{type: :consult_start}}
    :ok = Loop.prompt(loop, "And Genesis 8:1?")
    second = fold(Reply.new(1, @lead), &(&1.type == :agent_end))
    assert second.consult == nil
    assert {second.status, Enum.map(Reply.blocks(second), & &1["type"])} == {:done, ["SUMMARY"]}

    assert_receive {:rho, _, %{type: :consult_end, status: :ok}}, 2_000
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    refute_receive {:rho, _, %{type: :agent_start}}, 100

    assert [_, _, %Message{role: :user}, %Message{role: :agent} = last] = shown = messages(loop)
    assert summary(last) == "Second answer."
    assert Pushback.offered?(shown, last)
    assert [_lead, _critic, _lead_again] = FakeLLM.requests(llm)
  end

  test "stopping the loop stops the critique", %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    %{loop: loop, sup: sup} =
      start(dir, %{@lead => [[{:text, @answer}]], @critic => [[{:sleep, 5_000}]]})

    first = ask(loop)
    assert {:ok, task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)
    ref = Process.monitor(task)
    reply = fold(pushback(), &(&1.type == :consult_start))
    :ok = Loop.stop(loop)

    assert fold(reply).status == :stopped
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    assert [_, %Message{role: :agent}] = messages(loop)
  end

  test "the critic sees the pictures the question sent", %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])
    MaterialStore.install()
    put_env(:rho, :resolve_attachment, {Materials, :resolve, []})

    %{loop: loop, llm: llm, sup: sup} =
      start(dir, %{
        @lead => [[{:text, @answer}], [{:text, @response}]],
        @critic => [[{:text, @critique}]]
      })

    ctx = %{session_id: Loop.config(loop).session.id}
    {:ok, photo} = Materials.put(Materials.new("png bytes", name: "lamp.png"), "png bytes", ctx)

    picture = %{kind: :image, ref: photo.id, name: "lamp.png", mime: "image/png", about: "image"}
    first = ask(loop, [picture])
    assert first.status == :done

    assert {:ok, _task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)
    assert fold(pushback()).status == :done

    critic = Enum.find(FakeLLM.requests(llm), &(&1.model == @critic))
    parts = Enum.flat_map(critic.messages, & &1.content)
    assert Enum.any?(parts, &(&1.type == :image and &1.data == "png bytes"))
    assert text_of(List.last(critic.messages)) =~ ~s(name="lamp.png")
  end

  test "asked in words, the lead's own ask_model critique gets the study brief and is the round",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])
    put_env(:rho, :consult_system, {Pushback, :system, []})

    ask = %{
      "model" => @critic,
      "purpose" => "critique",
      "prompt" => "Check my answer about ruach.",
      "include_conversation" => true
    }

    %{loop: loop, llm: llm, sup: sup} =
      start(
        dir,
        %{
          @lead => [[{:tool_call, "c1", "ask_model", ask}], [{:text, @response}]],
          @critic => [[{:text, @critique}]]
        },
        [Lexicon, Rho.Tools.Consult]
      )

    :ok = Loop.prompt(loop, "Have Gemini push back on that.")
    streaming = fold(Reply.new(1, @lead), &(&1.type == :consult_delta))

    assert [%{"type" => "CONSULT", "text" => @critique, "model" => @critic}] =
             Reply.blocks(streaming)

    reply = fold(streaming)
    assert reply.status == :done

    critic = Enum.find(FakeLLM.requests(llm), &(&1.model == @critic))
    assert critic.system_prompt == Pushback.critic_prompt()

    [_, %Message{role: :agent} = answered] = shown = messages(loop)
    assert [%{"type" => "CONSULT", "purpose" => "critique"}, _sum] = answered.blocks
    refute Pushback.offered?(shown, answered)
    assert Pushback.auto(loop, reply, @critic, task_supervisor: sup) == :skip
    assert Pushback.target(branch(loop)) == {:error, :pushed_back}
  end

  test "a reply that failed or was stopped gets no automatic pushback", %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])
    %{loop: loop} = start(dir, %{@lead => lead_script()})
    first = ask(loop)

    for status <- [:error, :stopped, :running],
        do: assert(Pushback.auto(loop, %{first | status: status}, @critic) == :skip)
  end

  test "names: the title of a critique and of other purposes" do
    assert Pushback.title("google:no-such-model", "critique") == "Pushback · no-such-model"
    assert Pushback.title("google:x", "second_opinion") == "Second opinion · x"
    assert Pushback.title("google:x", "fact_check") == "Fact check · x"
  end

  defp text_of(%ReqLLM.Message{content: parts}), do: Enum.map_join(parts, "", &(&1.text || ""))
end
