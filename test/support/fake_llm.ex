defmodule Bezalel.Test.FakeLLM do
  @moduledoc """
  A scripted `Rho.LLM` with a script per model, so a lead and the model
  it consults answer from their own: each call to `model` plays that
  model's next reply. Steps: `{:text, s}`, `{:tool_call, id, name, args}`,
  `{:sleep, ms}`, `{:error, error}` (returns it). Every call sends the test
  `{:llm_request, request}`; `requests/1` has them all, in order.
  """
  @behaviour Rho.LLM

  @doc "`scripts`: `%{model => [reply]}`, each reply a list of steps."
  @spec start(%{String.t() => [[term()]]}, pid()) :: {:ok, pid()}
  def start(scripts, test \\ self()),
    do: Agent.start_link(fn -> %{scripts: scripts, requests: [], test: test} end)

  @spec requests(pid()) :: [map()]
  def requests(agent), do: Agent.get(agent, &Enum.reverse(&1.requests))

  @impl true
  def stream(request, agent, sink) do
    {reply, test} =
      Agent.get_and_update(agent, fn st ->
        {reply, rest} =
          case Map.get(st.scripts, request.model, []) do
            [reply | rest] -> {reply, rest}
            [] -> {[{:error, {:other, "no reply scripted for #{request.model}"}}], []}
          end

        {{reply, st.test},
         %{
           st
           | scripts: Map.put(st.scripts, request.model, rest),
             requests: [request | st.requests]
         }}
      end)

    send(test, {:llm_request, request})

    play(reply, sink, %{
      text: "",
      thinking: "",
      tool_calls: [],
      usage: usage(),
      finish_reason: :stop
    })
  end

  defp play([], _sink, acc), do: {:ok, acc}
  defp play([{:error, error} | _], _sink, _acc), do: {:error, error}

  defp play([{:text, s} | rest], sink, acc) do
    sink.({:text, s})
    play(rest, sink, %{acc | text: acc.text <> s})
  end

  defp play([{:sleep, ms} | rest], sink, acc) do
    Process.sleep(ms)
    play(rest, sink, acc)
  end

  defp play([{:tool_call, id, name, args} | rest], sink, acc) do
    call = %{"id" => id, "name" => name, "arguments" => args}
    play(rest, sink, %{acc | tool_calls: acc.tool_calls ++ [call], finish_reason: :tool_calls})
  end

  defp usage, do: %{input_tokens: 100, output_tokens: 20, total_cost: 0.001}
end

defmodule Bezalel.Test.CredentialStore do
  @moduledoc """
  rho's credential store in memory (`config :rho, :credential_store`), so
  a test signs a provider in without touching the machine's.
  `install/1` starts it with `providers` signed in by API key.
  """
  @behaviour Rho.CredentialStore

  use Agent

  import ExUnit.Callbacks, only: [start_supervised!: 1, on_exit: 1]

  def start_link(keys), do: Agent.start_link(fn -> keys end, name: __MODULE__)

  @doc "Signs `providers` in (API keys), for this test."
  def install(providers) do
    keys =
      Map.new(providers, fn p ->
        {"auth:#{p}", Jason.encode!(%{"type" => "api_key", "key" => "#{p}-key"})}
      end)

    start_supervised!({__MODULE__, keys})
    previous = Application.fetch_env(:rho, :credential_store)
    Application.put_env(:rho, :credential_store, __MODULE__)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:rho, :credential_store, value)
        :error -> Application.delete_env(:rho, :credential_store)
      end
    end)
  end

  @impl true
  def get(key), do: Agent.get(__MODULE__, &Map.fetch(&1, key))

  @impl true
  def put(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))

  @impl true
  def delete(key), do: Agent.update(__MODULE__, &Map.delete(&1, key))
end
