defmodule Bezalel.Agent.PushbackTest do
  # async: false: the sign-ins (`config :rho, :credential_store`) are app-wide.
  use ExUnit.Case, async: false

  alias Bezalel.Agent.{Pushback, Reply}
  alias Bezalel.Library.{Message, Transcript}
  alias Bezalel.Test.{CredentialStore, FakeLLM}
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

  defp start(dir, scripts) do
    {:ok, llm} = FakeLLM.start(scripts)
    sup = start_supervised!(Task.Supervisor, id: make_ref())

    loop =
      start_supervised!(
        {Loop,
         session: Session.new(dir, @lead, dir),
         entries: [],
         llm: {FakeLLM, llm},
         tools: [Lexicon],
         task_supervisor: sup,
         data_dir: dir,
         system_prompt: "study",
         retry_base_ms: 1},
        id: make_ref()
      )

    :ok = Loop.subscribe(loop)
    %{loop: loop, llm: llm, sup: sup}
  end

  # The loop's events folded into `reply` until the run ends (or the
  # pushback fails before it starts one).
  defp fold(reply, timeout \\ 2_000) do
    receive do
      {:rho, _sid, event} ->
        reply = Reply.apply(reply, event)

        case event.type do
          :agent_end -> reply
          :consult_end when event.status != :ok -> reply
          _ -> fold(reply, timeout)
        end
    after
      timeout -> flunk("no end; reply so far: #{inspect(reply)}")
    end
  end

  defp ask(loop) do
    :ok = Loop.prompt(loop, @question)
    fold(Reply.new(1, @lead))
  end

  defp branch(loop), do: Loop.snapshot(loop).entries
  defp messages(loop), do: Transcript.messages(branch(loop), "s")

  test "auto: after a finished reply the critic reviews it, then the lead answers the critique",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    %{loop: loop, llm: llm, sup: sup} =
      start(dir, %{@lead => lead_script(), @critic => [[{:text, @critique}]]})

    first = ask(loop)
    assert first.status == :done
    assert {:ok, task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)
    ref = Process.monitor(task)

    # The pushback streams as a reply of its own: the critique first.
    pushback = fold(Reply.new(1, @lead))
    assert pushback.status == :done
    assert_receive {:DOWN, ^ref, :process, _, :normal}

    assert [consult | rest] = Reply.blocks(pushback)
    assert consult["type"] == "CONSULT"

    assert {consult["model"], consult["purpose"], consult["text"]} ==
             {@critic, "critique", @critique}

    assert List.last(rest)["text"] == @response
    assert pushback.consult.entry in pushback.seen

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
    assert c.id == pushback.consult.entry
    assert Enum.find(response.blocks, &(&1["id"] == "sum"))["text"] == @response

    # One round: not on the answer again, not on the lead's response.
    shown = messages(loop)
    refute Pushback.offered?(shown, answer)
    refute Pushback.offered?(shown, response)
    assert Pushback.auto(loop, pushback, @critic, task_supervisor: sup) == :skip

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
    assert fold(Reply.new(1, @lead)).status == :done
    assert [_, _, %Message{role: :consult}, %Message{role: :agent}] = messages(loop)
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

  test "a critic that fails ends the pushback with its error; the lead isn't prompted",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    %{loop: loop, llm: llm, sup: sup} =
      start(dir, %{@lead => lead_script(), @critic => [[{:error, {:other, "quota gone"}}]]})

    first = ask(loop)
    assert {:ok, _task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)

    pushback = fold(Reply.new(1, @lead))
    assert pushback.status == :error
    assert pushback.error =~ "quota gone"
    assert pushback.consult.status == :error

    refute_receive {:rho, _, %{type: :agent_start}}, 100
    assert [%{model: @lead}, %{model: @lead}, %{model: @critic}] = FakeLLM.requests(llm)
    assert [_, %Message{role: :agent}] = messages(loop)
  end

  test "a critique that arrives while the lead is busy waits its turn, and is still answered",
       %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    scripts = %{
      @lead => [
        [{:text, @answer}],
        [{:sleep, 300}, {:text, "Second answer."}],
        [{:text, @response}]
      ],
      @critic => [[{:sleep, 100}, {:text, @critique}]]
    }

    %{loop: loop, sup: sup} = start(dir, scripts)
    first = ask(loop)
    assert {:ok, _task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)
    # The user asks again before the critique is in.
    :ok = Loop.prompt(loop, "And Genesis 8:1?")

    # The run the question started goes on with the queued critique: one
    # run, the critique and its answer after the second answer.
    reply = fold(Reply.new(1, @lead), 3_000)
    assert {reply.status, reply.consult.status} == {:done, :ok}

    assert [
             _,
             _,
             %Message{role: :user},
             %Message{role: :agent},
             %Message{role: :consult},
             response
           ] =
             messages(loop)

    assert Enum.find(response.blocks, &(&1["id"] == "sum"))["text"] == @response
  end

  test "stopping the loop stops the critique", %{tmp_dir: dir} do
    CredentialStore.install([:anthropic, :google])

    %{loop: loop, sup: sup} =
      start(dir, %{@lead => [[{:text, @answer}]], @critic => [[{:sleep, 5_000}]]})

    first = ask(loop)
    assert {:ok, task} = Pushback.auto(loop, first, @critic, task_supervisor: sup)
    ref = Process.monitor(task)
    assert_receive {:rho, _, %{type: :consult_start}}
    :ok = Loop.stop(loop)

    assert_receive {:rho, _, %{type: :consult_end, status: :stopped} = ended}
    assert Reply.apply(Reply.new(1, @lead), ended).status == :stopped
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    assert [_, %Message{role: :agent}] = messages(loop)
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
    assert Pushback.system("critique") == Pushback.critic_prompt()
    assert Pushback.system("second_opinion") == nil
  end

  defp text_of(%ReqLLM.Message{content: parts}), do: Enum.map_join(parts, "", &(&1.text || ""))
end
