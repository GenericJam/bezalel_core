defmodule Bezalel.UsageTest do
  use ExUnit.Case, async: true

  alias Bezalel.Library.Transcript
  alias Bezalel.Usage
  alias ReqLLM.Streaming.Failure
  alias Rho.LLM.ReqLLM, as: Adapter
  alias Rho.Session

  @claude "anthropic:claude-sonnet-4-5"
  @gpt "openai:gpt-5.1"
  @codex "openai_codex:gpt-5.1-codex"

  @oauth %{signed_in: true, type: :oauth, email: "k@example.com", expires: nil}
  @key %{signed_in: true, type: :api_key, email: nil, expires: nil}
  @out %{signed_in: false, type: nil, email: nil, expires: nil}

  # A provider's error response as rho sees it: the body through req_llm's
  # failure (what a streamed call raises), rho's normalize, and for a 429 or
  # 529 its rate-limit reading of the headers; then the text the loop puts
  # in the reply (`Rho.LLM.describe/1`).
  defp failed(model, status, body, headers \\ [], state \\ %{}, now \\ now()) do
    status
    |> Failure.api_error(Jason.encode!(body), headers)
    |> Adapter.normalize()
    |> Adapter.limit(model, headers, body, state, now)
  end

  defp now, do: System.os_time(:second)

  defp auth(pairs),
    do: Map.merge(%{anthropic: @out, openai_codex: @out, openai: @out}, Map.new(pairs))

  # The credentials are always the test's (the default reads the node's
  # store): none signed in unless the test says.
  defp explain(error, opts \\ []),
    do: Usage.explain(error, Keyword.put_new(opts, :auth, auth([])))

  defp preflight(state, model, opts),
    do: Usage.preflight(state, model, Keyword.put_new(opts, :auth, auth(anthropic: @oauth)))

  describe "explain/2: a failed call in plain words" do
    test "an Anthropic API key out of credit (a 400) says to add credit, with the billing page" do
      text =
        @claude
        |> failed(400, %{
          "type" => "error",
          "error" => %{
            "type" => "invalid_request_error",
            "message" =>
              "Your credit balance is too low to access the Anthropic API. " <>
                "Please go to Plans & Billing to upgrade or purchase credits."
          },
          "request_id" => "req_011CUjsGq1H6Ew3vGq5Lz1Ab"
        })
        |> Rho.LLM.describe()

      e = explain(text, model: @claude, auth: auth(anthropic: @key))

      assert %{kind: :no_credit, action: :add_credit, provider: :anthropic} = e
      assert e.billing_url == "https://console.anthropic.com/settings/billing"
      assert e.message =~ "Anthropic account has run out of credit"
      assert e.detail == text
    end

    test "OpenAI's insufficient_quota (a 429 the loop retried) is out of credit, not a throttle" do
      error =
        failed(@gpt, 429, %{
          "error" => %{
            "message" =>
              "You exceeded your current quota, please check your plan and billing details. " <>
                "For more information on this error, read the docs: " <>
                "https://platform.openai.com/docs/guides/error-codes/api-errors.",
            "type" => "insufficient_quota",
            "param" => nil,
            "code" => "insufficient_quota"
          }
        })

      assert {:rate_limited, %{resets_at: nil}} = error

      text =
        Rho.LLM.describe(error) <>
          "\nStill limited after 3 retries over 14 s: prompt again to continue this run."

      e = explain(text, model: @gpt)

      assert %{kind: :no_credit, action: :add_credit, provider: :openai} = e
      assert e.billing_url =~ "platform.openai.com"
    end

    test "Anthropic's 529 overloaded is the provider's load, to try again" do
      error =
        failed(@claude, 529, %{
          "type" => "error",
          "error" => %{"type" => "overloaded_error", "message" => "Overloaded"}
        })

      e = explain(Rho.LLM.describe(error), model: @claude)

      assert %{kind: :overloaded, action: :retry, until: nil} = e
      assert e.message =~ "Anthropic's servers are too busy"
      assert e.message =~ "this isn't your usage"
    end

    test "a Claude subscription's 5-hour window used up: wait until it resets, or switch" do
      now = now()
      reset = now + 4800

      headers = [
        {"anthropic-ratelimit-unified-5h-utilization", "1.0"},
        {"anthropic-ratelimit-unified-5h-reset", Integer.to_string(reset)},
        {"anthropic-ratelimit-unified-7d-utilization", "0.41"},
        {"anthropic-ratelimit-unified-7d-reset", Integer.to_string(now + 3 * 86_400)},
        {"retry-after", "4800"}
      ]

      body = %{
        "type" => "error",
        "error" => %{
          "type" => "rate_limit_error",
          "message" =>
            "This request would exceed your account's rate limit. Please try again later."
        }
      }

      error = failed(@claude, 429, body, headers, %{}, now)
      assert {:rate_limited, %{resets_at: ^reset, window: "5 hours"}} = error

      # The loop's text, and the usage record the same call left.
      text = Rho.LLM.describe(error)
      state = recorded(@claude, %{status: 429, headers: headers, body: body, error: "x"}, now)

      e = explain(text, state: state, model: @claude, now: now)

      assert %{kind: :limit_reached, action: :wait, until: ^reset, provider: :anthropic} = e
      assert e.title == "Usage limit reached"
      assert e.message =~ "Claude's 5-hour limit is used up."
      assert e.message =~ "It resets at #{Rho.LLM.clock(reset, now)} (in 1h 20m)."
      assert e.message =~ "switch to another model"

      # The error itself, as a host holding it would pass it.
      assert %{kind: :limit_reached, until: ^reset} = explain(error, now: now)

      # Only the text, with no record: the window still comes from the words.
      bare = explain(text, now: now)
      assert %{kind: :limit_reached, until: nil, action: :switch_model} = bare
      assert bare.message =~ "Claude's 5-hour limit is used up. Switch to another model"
      refute bare.message =~ "Until then"

      # The host says how a time reads (the website: the reader's zone).
      timed = explain(text, state: state, now: now, clock: fn ^reset -> "5:10 AM MDT" end)
      assert timed.message =~ "It resets at 5:10 AM MDT (in 1h 20m)."
    end

    test "the loop's note on the fallback model doesn't stand for the call that failed" do
      overloaded =
        failed(@claude, 529, %{
          "type" => "error",
          "error" => %{"type" => "overloaded_error", "message" => "Overloaded"}
        })

      text =
        Rho.LLM.describe(overloaded) <>
          "\nStill limited after 4 retries over 31 s: prompt again to continue this run." <>
          "\n(Fallback model: ChatGPT (OpenAI Codex)'s 5 hours limit is used up until 05:10.)"

      assert %{kind: :overloaded, provider: :anthropic, detail: ^text} =
               explain(text, model: @claude)

      throttle =
        Rho.LLM.describe({:http, 429, "This request would exceed your account's rate limit."}) <>
          "\nPrompt again to continue this run." <>
          "\n(Fallback model: ChatGPT (OpenAI Codex)'s 7 days limit is used up until Oct 21 09:00.)"

      assert %{kind: :rate_limited, provider: :anthropic} = explain(throttle, model: @claude)
    end

    test "Gemini's per-minute quota is a throttle, though it reads like OpenAI's out of credit" do
      error =
        failed("google:gemini-2.5-flash", 429, %{
          "error" => %{
            "code" => 429,
            "message" =>
              "You exceeded your current quota, please check your plan and billing details. " <>
                "For more information on this error, head to: " <>
                "https://ai.google.dev/gemini-api/docs/rate-limits.",
            "status" => "RESOURCE_EXHAUSTED"
          }
        })

      assert %{kind: :rate_limited, action: :retry, billing_url: nil} =
               explain(Rho.LLM.describe(error), model: "google:gemini-2.5-flash")
    end

    test "ChatGPT's usage limit (Codex's body) resets when the body says" do
      now = now()

      body = %{
        "error" => %{
          "type" => "usage_limit_reached",
          "message" => "The usage limit has been reached",
          "plan_type" => "plus",
          "resets_at" => now + 7200,
          "resets_in_seconds" => 7200
        }
      }

      error = failed(@codex, 429, body, [], %{}, now)
      e = explain(Rho.LLM.describe(error), model: @codex, state: %{}, now: now)

      assert %{kind: :limit_reached, provider: :openai_codex} = e
      assert e.message =~ "ChatGPT's usage limit is used up."

      assert %{kind: :limit_reached, until: until, action: :wait} =
               explain(error, now: now)

      assert until == now + 7200
    end

    test "a short throttle is to try again in a moment" do
      error =
        failed(@claude, 429, %{
          "type" => "error",
          "error" => %{
            "type" => "rate_limit_error",
            "message" =>
              "This request would exceed the rate limit for your organization of 50,000 input tokens per minute."
          }
        })

      e = explain(Rho.LLM.describe(error), model: @claude)
      assert %{kind: :rate_limited, action: :retry, until: nil} = e
      assert e.message =~ "Anthropic is limiting how fast requests can be made"
    end

    test "a rejected key (Anthropic's, OpenAI's) is to paste a working one" do
      anthropic =
        @claude
        |> failed(401, %{
          "type" => "error",
          "error" => %{"type" => "authentication_error", "message" => "invalid x-api-key"}
        })
        |> Rho.LLM.describe()

      openai =
        @gpt
        |> failed(401, %{
          "error" => %{
            "message" =>
              "Incorrect API key provided: sk-proj-****abcd. You can find your API key at " <>
                "https://platform.openai.com/account/api-keys.",
            "type" => "invalid_request_error",
            "param" => nil,
            "code" => "invalid_api_key"
          }
        })
        |> Rho.LLM.describe()

      assert %{kind: :invalid_key, action: :add_key, provider: :anthropic} =
               e = explain(anthropic, model: @claude)

      assert e.message =~ "Anthropic API key was turned down"
      assert %{kind: :invalid_key, provider: :openai} = explain(openai, model: @gpt)

      # OpenAI words a ChatGPT sign-in's bad token the same; there's no key
      # to paste there, and a sign-in is signed in to again.
      assert %{kind: :sign_in_expired, action: :sign_in, provider: :openai_codex} =
               explain(openai, model: @codex)

      assert %{kind: :sign_in_expired, action: :sign_in} =
               explain(anthropic, model: @claude, auth: auth(anthropic: @oauth))
    end

    test "a 401 is an expired sign-in on a subscription and a bad key on an API key" do
      text =
        @claude
        |> failed(401, %{
          "type" => "error",
          "error" => %{
            "type" => "authentication_error",
            "message" =>
              "OAuth token has expired. Please obtain a new token or refresh your existing token."
          }
        })
        |> Rho.LLM.describe()

      assert %{kind: :sign_in_expired, action: :sign_in} =
               e = explain(text, model: @claude, auth: auth(anthropic: @oauth))

      assert e.message =~ "Claude sign-in has expired"

      generic = Rho.LLM.describe({:http, 401, "Invalid bearer token"})

      assert %{kind: :invalid_key, action: :add_key} =
               explain(generic, model: @claude, auth: auth(anthropic: @key))

      assert %{kind: :sign_in_expired} =
               explain(generic, model: @claude, auth: auth(anthropic: @oauth))
    end

    test "a refresh that failed, a missing sign-in, the daily cap, the network, anything else" do
      expired = {:auth, :openai_codex, "invalid_grant: refresh token revoked"}
      assert %{kind: :sign_in_expired, action: :sign_in} = explain(expired)
      assert %{kind: :sign_in_expired} = explain(Rho.LLM.describe(expired))

      assert %{kind: :signed_out, action: :sign_in, provider: :openai} =
               explain({:signed_out, :openai})

      assert %{kind: :signed_out, provider: :openai} =
               explain(Rho.LLM.describe({:signed_out, :openai}))

      cap =
        "Daily cost cap reached: $5.02 of $5.00 spent today. " <>
          "No more model calls until tomorrow, or until the cap is raised."

      assert %{kind: :cost_cap, action: :wait} = explain(cap)

      assert %{kind: :network, action: :retry} = explain({:transport, :econnrefused})

      assert %{kind: :network} =
               explain(Rho.LLM.describe({:transport, :closed}), model: @claude)

      other = Rho.LLM.describe({:http, 500, "Internal server error"}) <> "\nPrompt again."

      assert %{kind: :failed, action: :retry, message: "Model call failed (HTTP 500): " <> _} =
               e = explain(other)

      refute e.message =~ "Prompt again"
    end
  end

  describe "summary/2: Settings → Usage" do
    @tag :tmp_dir
    test "a subscription's windows with their resets, levels and plan", %{tmp_dir: dir} do
      now = 1_800_000_000

      # Claude's usage endpoint (GET /api/oauth/usage), as Rho.Usage.Fetch stores it.
      body = %{
        "five_hour" => %{"utilization" => 42.0, "resets_at" => iso(now + 4800)},
        "seven_day" => %{"utilization" => 83.4, "resets_at" => iso(now + 2 * 86_400 + 3600)},
        "seven_day_opus" => %{"utilization" => 100.0, "resets_at" => iso(now + 5 * 86_400)}
      }

      # Claude's endpoint names no plan (ChatGPT's does).
      {windows, nil} = Rho.Usage.from_endpoint(:anthropic, body, now)
      :ok = Rho.Usage.put_endpoint(dir, :anthropic, windows, nil, now)
      state = Rho.Usage.load(dir)

      [claude] = Usage.summary(state, now: now, auth: auth(anthropic: @oauth))

      assert %{provider: :anthropic, name: "Claude", kind: :subscription, plan: nil} = claude
      assert claude.checked_at == now
      assert claude.billing_url == nil
      assert claude.level == :exhausted

      assert [
               %{id: "5h", label: "5-hour limit", percent: 42, resets_in: "1h 20m", level: :ok},
               %{id: "7d", label: "Weekly limit", percent: 83, resets_in: "2d 1h", level: :warn},
               %{id: "7d_opus", label: "Weekly limit (Opus)", percent: 100, level: :exhausted}
             ] = claude.windows

      assert %{label: "Weekly limit (Opus)", resets_in: "5d 0h"} = claude.exhausted

      # Five hours later the 5-hour window has reset: 0 %, no reset time.
      [later] = Usage.summary(state, now: now + 5 * 3600, auth: auth(anthropic: @oauth))
      assert %{percent: 0, resets_at: nil, resets_in: nil, level: :ok} = hd(later.windows)
    end

    @tag :tmp_dir
    test "an API key's spend today and this week, per model, with the billing page",
         %{tmp_dir: dir} do
      today = ~D[2026-10-18]
      now = 1_800_000_000

      call = fn input, output, cost ->
        %{
          status: 200,
          headers: [],
          usage: %{input_tokens: input, output_tokens: output, total_cost: cost}
        }
      end

      :ok = Rho.Usage.record(dir, @claude, call.(12_000, 800, 0.0480), now, today)
      :ok = Rho.Usage.record(dir, @claude, call.(3_000, 200, 0.0120), now, today)

      :ok =
        Rho.Usage.record(
          dir,
          "anthropic:claude-opus-4-1",
          call.(9_000, 1_000, 0.21),
          now,
          ~D[2026-10-14]
        )

      # Eight days ago: outside the week.
      :ok = Rho.Usage.record(dir, @claude, call.(50_000, 5_000, 1.0), now, ~D[2026-10-10])
      :ok = Rho.Usage.record(dir, @gpt, call.(1_000, 100, 0.002), now, today)

      state = Rho.Usage.load(dir)
      opts = [now: now, today: today, auth: auth(anthropic: @key, openai: @key)]

      [anthropic, openai] = Usage.summary(state, opts)

      assert %{name: "Anthropic API key", kind: :api_key, windows: [], level: :ok} = anthropic
      assert anthropic.billing_url == "https://console.anthropic.com/settings/billing"
      assert %{requests: 2, input: 15_000, output: 1_000} = anthropic.spend.today
      assert_in_delta anthropic.spend.today.cost, 0.06, 1.0e-9
      assert_in_delta anthropic.spend.week.cost, 0.27, 1.0e-9
      assert anthropic.spend.week.tokens == 26_000

      assert [%{model: "anthropic:claude-sonnet-4-5"}, %{model: "anthropic:claude-opus-4-1"}] =
               anthropic.models

      assert %{
               provider: :openai,
               name: "OpenAI API key",
               billing_url: "https://platform.openai.com" <> _
             } =
               openai

      assert %{text: "Anthropic API key · $0.06 today", level: :ok, kind: :api_key} =
               Usage.meter(state, @claude, opts)

      assert %{text: "OpenAI API key · <$0.01 today"} = Usage.meter(state, @gpt, opts)

      # Signed out providers aren't listed, nor metered.
      assert [%{provider: :openai}] =
               Usage.summary(state, Keyword.put(opts, :auth, auth(openai: @key)))

      assert Usage.meter(state, @claude, Keyword.put(opts, :auth, auth(openai: @key))) == nil
    end
  end

  describe "meter/3 and preflight/3" do
    test "the fullest window, a warning past 80 %, and used up with its reset" do
      now = 1_800_000_000
      opts = [now: now, auth: auth(anthropic: @oauth)]

      state = windows(%{"5h" => {42.0, now + 4800}, "7d" => {18.0, now + 86_400}}, now)

      assert %{text: "Claude · 5-hour limit 42% · resets in 1h 20m", level: :ok} =
               Usage.meter(state, @claude, opts)

      warn = windows(%{"5h" => {12.0, now + 600}, "7d" => {86.0, now + 90_000}}, now)

      assert %{text: "Claude · Weekly limit 86% · resets in 1d 1h", level: :warn} =
               Usage.meter(warn, @claude, opts)

      full = windows(%{"5h" => {100.0, now + 4800}, "7d" => {64.0, now + 90_000}}, now)

      assert %{text: "Claude · 5-hour limit used up · resets in 1h 20m", level: :exhausted} =
               Usage.meter(full, @claude, opts)

      # No figures yet: nothing to show.
      assert Usage.meter(%{}, @claude, opts) == nil
    end

    test "preflight stops a question to a used-up subscription, with the explanation" do
      now = 1_800_000_000
      full = windows(%{"5h" => {100.0, now + 4800}, "7d" => {64.0, now + 90_000}}, now)

      assert {:exhausted, e} = preflight(full, @claude, now: now)
      assert %{kind: :limit_reached, action: :wait, until: until, provider: :anthropic} = e
      assert until == now + 4800
      assert e.message =~ "Claude's 5-hour limit is used up. It resets at "

      # Another provider's model goes ahead, and so does one about to reset.
      assert preflight(full, @codex, now: now) == :ok
      assert preflight(full, @claude, now: now + 4800 - 30) == :ok
      assert preflight(%{}, @claude, now: now) == :ok

      # A recorded 429 that hasn't lifted counts as used up too.
      limited = %{"rate_limited" => %{"anthropic" => %{"at" => now, "resets_at" => now + 900}}}

      assert {:exhausted, %{until: lifts, message: message}} =
               preflight(limited, @claude, now: now)

      assert lifts == now + 900
      assert message =~ "Claude's usage limit is used up."
    end

    @tag :tmp_dir
    test "a throttle's 429 doesn't stand for a used-up limit, and a later call supersedes one",
         %{tmp_dir: dir} do
      now = 1_800_000_000
      opts = [now: now + 20, auth: auth(anthropic: @oauth)]
      five_hours = Integer.to_string(now + 4 * 3600)

      throttle = %{
        status: 429,
        body: %{"type" => "error", "error" => %{"type" => "rate_limit_error"}},
        error: "This request would exceed your account's rate limit.",
        headers: [
          {"retry-after", "5"},
          {"anthropic-ratelimit-unified-reset", five_hours},
          {"anthropic-ratelimit-unified-5h-utilization", "0.3"},
          {"anthropic-ratelimit-unified-5h-reset", five_hours}
        ]
      }

      # rho keeps the 429 with Claude's unified reset, four hours away; the
      # windows the same response reported say there's room.
      :ok = Rho.Usage.record(dir, @claude, throttle, now)
      state = Rho.Usage.load(dir)
      assert %{"resets_at" => reset} = Rho.Usage.rate_limited(state, :anthropic)
      assert reset == now + 4 * 3600

      assert preflight(state, @claude, opts) == :ok

      assert %{level: :ok, text: "Claude · 5-hour limit 30% · resets in 3h 59m"} =
               Usage.meter(state, @claude, opts)

      assert %{kind: :rate_limited, until: nil, action: :retry} =
               explain(Rho.LLM.describe({:http, 429, throttle.error}), state: state, now: now)

      # rho's own text calls that throttle a used-up limit; its reset isn't trusted either.
      used_up = "Claude (Anthropic)'s usage limit is used up until 20:40."

      assert %{kind: :limit_reached, until: nil, action: :switch_model} =
               explain(used_up, state: state, now: now, model: @claude)

      # A 429 with no windows is the latest word until a call or a Refresh says more.
      bare = Map.put(throttle, :headers, [{"anthropic-ratelimit-unified-reset", five_hours}])
      :ok = Rho.Usage.record(dir, @claude, bare, now + 10)
      assert {:exhausted, _} = preflight(Rho.Usage.load(dir), @claude, opts)

      ok = %{status: 200, headers: [{"anthropic-ratelimit-unified-5h-utilization", "0.31"}]}
      :ok = Rho.Usage.record(dir, @claude, Map.put(ok, :usage, %{input_tokens: 1}), now + 15)
      assert preflight(Rho.Usage.load(dir), @claude, opts) == :ok
    end

    test "a key stored in place of a used-up sign-in isn't held back by the sign-in's windows" do
      now = 1_800_000_000
      # The weekly window the Claude sign-in left at 100 %, three days from resetting.
      stale = windows(%{"5h" => {30.0, now + 600}, "7d" => {100.0, now + 3 * 86_400}}, now)
      key = [now: now, auth: auth(anthropic: @key)]

      assert {:exhausted, _} = preflight(stale, @claude, now: now)
      assert preflight(stale, @claude, key) == :ok

      assert [%{kind: :api_key, windows: [], exhausted: nil, level: :ok, plan: nil}] =
               Usage.summary(stale, key)

      assert %{kind: :api_key, level: :ok} = Usage.meter(stale, @claude, key)
    end
  end

  describe "reply_usage/1" do
    test "a reply's tokens and cost over its calls, and none without tokens" do
      first =
        assistant(%{
          input_tokens: 15_200,
          cache_read_tokens: 12_000,
          output_tokens: 310,
          total_cost: 0.021
        })

      last =
        assistant(%{
          input_tokens: 16_000,
          cache_read_tokens: 15_000,
          output_tokens: 940,
          total_cost: 0.019
        })

      assert %{input: 4_200, output: 1_250, cache_read: 27_000, cache_write: 0} =
               u = Usage.reply_usage([first, last])

      assert_in_delta u.cost, 0.04, 1.0e-9
      assert u.text == "in 4.2k · out 1.3k · cache 27.0k · $0.04"
      assert Usage.reply_usage([assistant(nil)]) == nil
    end

    test "the transcript's replies carry it" do
      branch = [
        "What does bara mean?" |> Transcript.user() |> Map.put("id", "u1"),
        %{text: "To create.", stop_reason: "stop", usage: %{input_tokens: 900, output_tokens: 40}}
        |> Session.assistant(@claude)
        |> Map.put("id", "a1")
      ]

      # No cost reported (a sign-in's calls report none): none shown.
      assert [%{usage: nil}, %{usage: %{input: 900, output: 40, text: "in 900 · out 40"}}] =
               Transcript.messages(branch, "s1")
    end
  end

  test "token counts and dollars, short" do
    assert Enum.map([0, 987, 1_250, 12_340, 99_960, 999_999, 4_500_000], &Usage.tokens/1) ==
             ["0", "987", "1.3k", "12.3k", "100k", "1.0M", "4.5M"]

    assert Enum.map([0, 0.004, 0.84, 12.3], &Usage.money/1) == [
             "$0.00",
             "<$0.01",
             "$0.84",
             "$12.30"
           ]
  end

  # ── helpers ──

  defp recorded(model, call, now) do
    dir = Path.join(System.tmp_dir!(), "bezalel-usage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok = Rho.Usage.record(dir, model, call, now)
    Rho.Usage.load(dir)
  end

  # Claude's windows as the headers leave them: id => {percent used, reset}.
  defp windows(windows, now) do
    labels = %{"5h" => "5 hours", "7d" => "7 days"}

    stored =
      Map.new(windows, fn {id, {used, at}} ->
        {id, %{"label" => labels[id], "used" => used, "resets_at" => at}}
      end)

    %{
      "limits" => %{
        "anthropic" => %{"windows" => stored, "checked_at" => now, "source" => "headers"}
      }
    }
  end

  defp assistant(usage),
    do: Session.assistant(%{text: "…", stop_reason: "stop", usage: usage}, @claude)

  defp iso(unix), do: unix |> DateTime.from_unix!() |> DateTime.to_iso8601()
end
