defmodule Bezalel.Usage do
  @moduledoc """
  What every Bezalel app shows of the model providers' usage, so running out
  is never a mystery: a summary per signed-in provider (Settings → Usage), a
  short meter beside the model's name, a reply's own tokens and cost, a
  check before sending, and a plain explanation of a failed model call.

  It reads `Rho.Usage`'s record (`Rho.Usage.load/1` of rho's data dir, the
  `state` argument) and returns plain data; the host draws it. Times are
  unix seconds (`:now`, default the clock); days are the node's local dates
  (`:today`, default `Rho.Budget.today/0`), as rho records them. `:auth` is
  `Rho.Auth.status/0`'s map (its default).

    * A **subscription** (a Claude or ChatGPT sign-in) has windows: the
      share of each limit used (5-hour, weekly, per model) and when it
      resets, from the providers' headers on every call and their usage
      endpoints (`Rho.Usage.Fetch.refresh/3`).
    * An **API key** has no balance the provider will tell: what it spent
      (`cost`, from the token prices) today and this week, and the
      provider's billing page (`billing_url/1`).

  A level is `:ok`, `:warn` (a window at #{80} % or more) or `:exhausted`.
  """

  alias Rho.Auth

  @warn_at 80
  # A limit that lifts within a minute isn't worth stopping a question for
  # (the loop waits it out), as `Rho.LLM.usable/3` judges.
  @grace_s 60

  @billing %{
    anthropic: "https://console.anthropic.com/settings/billing",
    openai: "https://platform.openai.com/settings/organization/billing/overview",
    google: "https://aistudio.google.com/usage"
  }

  @type level :: :ok | :warn | :exhausted
  @type kind :: :subscription | :api_key

  @type totals :: %{
          tokens: non_neg_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer(),
          cost: float(),
          requests: non_neg_integer(),
          errors: non_neg_integer()
        }

  @type window :: %{
          id: String.t(),
          label: String.t(),
          percent: non_neg_integer(),
          resets_at: integer() | nil,
          resets_in: String.t() | nil,
          level: level()
        }

  @type provider_summary :: %{
          provider: Auth.provider(),
          name: String.t(),
          kind: kind(),
          plan: String.t() | nil,
          checked_at: integer() | nil,
          level: level(),
          windows: [window()],
          exhausted: %{label: String.t(), resets_at: integer(), resets_in: String.t()} | nil,
          spend: %{today: totals(), week: totals()},
          models: [%{model: String.t(), today: totals(), week: totals()}],
          billing_url: String.t() | nil
        }

  @type meter :: %{text: String.t(), level: level(), provider: Auth.provider(), kind: kind()}

  @type action :: :wait | :retry | :switch_model | :add_credit | :add_key | :sign_in

  @type explanation :: %{
          kind:
            :limit_reached
            | :rate_limited
            | :overloaded
            | :no_credit
            | :cost_cap
            | :invalid_key
            | :sign_in_expired
            | :signed_out
            | :network
            | :failed,
          title: String.t(),
          message: String.t(),
          action: action(),
          provider: Auth.provider() | nil,
          until: integer() | nil,
          billing_url: String.t() | nil,
          detail: String.t()
        }

  @type reply_usage :: %{
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer(),
          cost: float(),
          text: String.t()
        }

  # ── Settings → Usage ─────────────────────────────────────────────────────

  @doc """
  Every signed-in provider's usage, in `Rho.Auth.providers/0`'s order
  (`:providers` narrows and orders them): its windows and the worst level
  among them for a subscription, the billing page for an API key, and for
  both what its models used today and this week (the last seven days,
  today included), in total (`spend`) and per model (most tokens first).

  Windows are a sign-in's only: Claude's sign-in and an Anthropic key are
  the same provider in rho's record, and the windows a sign-in left there
  don't apply to a key stored in its place.
  """
  @spec summary(map(), keyword()) :: [provider_summary()]
  def summary(state, opts \\ []) do
    {now, today, auth} = context(opts)

    for provider <- Keyword.get(opts, :providers, Auth.providers()),
        %{signed_in: true, type: type} <- [auth[provider]] do
      kind = kind(type)
      models = models(state, provider, today)

      {windows, limits, out} =
        if kind == :subscription,
          do:
            {windows(state, provider, now), Rho.Usage.limits(state, provider) || %{},
             exhausted(state, provider, now)},
          else: {[], %{}, nil}

      %{
        provider: provider,
        name: name(provider, kind),
        kind: kind,
        plan: limits["plan"],
        checked_at: limits["checked_at"],
        level: worst([if(out, do: :exhausted, else: :ok) | Enum.map(windows, & &1.level)]),
        windows: windows,
        exhausted: out,
        spend: %{today: sum(models, :today), week: sum(models, :week)},
        models: models,
        billing_url: if(kind == :api_key, do: billing_url(provider))
      }
    end
  end

  @doc "A provider's billing page, where an API key's credit is bought (nil for a sign-in only)."
  @spec billing_url(Auth.provider()) :: String.t() | nil
  def billing_url(provider), do: @billing[provider]

  # ── The meter beside the model ───────────────────────────────────────────

  @doc """
  One line for the model in use: on a subscription its fullest window
  (`"Claude · 5-hour limit 42% · resets in 1h 20m"`, or `"… used up ·
  resets in …"`), on an API key what it spent today (`"Anthropic API key
  · $0.84 today"`). Nil when the model's provider isn't signed in, or a
  subscription has no figures yet (before its first call or Refresh).
  """
  @spec meter(map(), String.t(), keyword()) :: meter() | nil
  def meter(state, model, opts \\ []) do
    {now, today, auth} = context(opts)

    with {:ok, provider} <- Auth.provider_for_model(model),
         %{signed_in: true, type: type} <- auth[provider] do
      kind = kind(type)
      name = name(provider, kind)

      case kind do
        :subscription -> subscription_meter(state, provider, name, now)
        :api_key -> key_meter(state, provider, name, today)
      end
    else
      _ -> nil
    end
  end

  defp subscription_meter(state, provider, name, now) do
    case {exhausted(state, provider, now), windows(state, provider, now)} do
      {%{} = out, _} ->
        plan_meter(
          "#{name} · #{out.label} used up · resets in #{out.resets_in}",
          :exhausted,
          provider
        )

      {nil, []} ->
        nil

      # The fullest window (the first of equals: 5-hour before weekly).
      {nil, windows} ->
        w = Enum.max_by(windows, & &1.percent)
        resets = if w.resets_in, do: " · resets in #{w.resets_in}", else: ""
        plan_meter("#{name} · #{w.label} #{w.percent}%#{resets}", w.level, provider)
    end
  end

  defp key_meter(state, provider, name, today) do
    spent = sum(models(state, provider, today), :today).cost
    %{text: "#{name} · #{money(spent)} today", level: :ok, provider: provider, kind: :api_key}
  end

  defp plan_meter(text, level, provider),
    do: %{text: text, level: level, provider: provider, kind: :subscription}

  # ── Before sending ───────────────────────────────────────────────────────

  @doc """
  Can a question go to `model` now, as far as the usage record knows?
  `{:exhausted, explanation}` while its subscription's limit is used up
  for more than a minute (a window at 100 %, or a 429 that hasn't lifted),
  so the app can say so instead of sending a call that fails. An API key
  isn't held back: the windows are a sign-in's, and a key's throttles are
  short (the loop waits them out). Options as `explain/2`'s.
  """
  @spec preflight(map(), String.t(), keyword()) :: :ok | {:exhausted, explanation()}
  def preflight(state, model, opts \\ []) do
    {now, _today, auth} = context(opts)

    with {:ok, provider} <- Auth.provider_for_model(model),
         :subscription <- credential_kind(provider, auth),
         %{resets_at: at} when at > now + @grace_s <- used_up(state, provider, now) do
      {:exhausted, limit_reached(ctx(state, now, opts), provider, nil, "", nil)}
    else
      _ -> :ok
    end
  end

  # ── A failed model call ──────────────────────────────────────────────────

  @doc """
  What went wrong with a model call, in plain words, and what to do: wait
  until a time, try again, switch model, add credit (with the billing
  page), paste a new key, or sign in again.

  `error` is the reply's error text (what `Rho.LLM.describe/1` wrote, as
  the loop reports and the session keeps it) or a `t:Rho.LLM.error/0`.
  Options: `:state` (the usage record: when a used-up limit resets),
  `:model` (the model the call went to), `:auth` (whether its provider is
  a sign-in or a key: an API key's 401 is a bad key, a sign-in's an
  expired one), `:now`, and `:clock` (`fn unix -> text`, how the message
  says a reset time; `Rho.LLM.clock/2` by default, the node's local time:
  right on a phone, the server's zone on a website). `detail` keeps the
  original text.
  """
  @spec explain(String.t() | Rho.LLM.error(), keyword()) :: explanation()
  def explain(error, opts \\ []) do
    {now, _today, auth} = context(opts)
    ctx = ctx(Keyword.get(opts, :state, %{}), now, opts)
    text = text(error)
    # The loop adds why its fallback model couldn't take over; the call
    # that failed is the text before it.
    own = text |> String.split("\n(Fallback model:", parts: 2) |> hd()
    provider = provider(error, opts[:model], own)
    kind = credential_kind(provider, auth)

    case classify(error, String.downcase(own), provider, now) do
      :limit_reached -> limit_reached(ctx, provider, window_in(own), text, error)
      class -> explanation(class, provider, kind, ctx, text)
    end
  end

  defp ctx(state, now, opts),
    do: %{state: state, now: now, clock: Keyword.get(opts, :clock, &Rho.LLM.clock(&1, now))}

  defp text(error) when is_binary(error), do: error
  defp text(error), do: Rho.LLM.describe(error)

  defp classify({:rate_limited, %{resets_at: at}}, _t, _provider, now)
       when is_integer(at) and at > now,
       do: :limit_reached

  defp classify({:signed_out, _provider}, _t, _p, _now), do: :signed_out
  defp classify({:auth, _provider, _message}, _t, _p, _now), do: :sign_in_expired
  defp classify({:transport, _reason}, _t, _p, _now), do: :network

  defp classify(_error, t, provider, _now) do
    Enum.find_value(classes(provider), :failed, fn {class, needles} ->
      if Enum.any?(needles, &String.contains?(t, &1)), do: class
    end)
  end

  # In order: the first class one of whose phrases the (lowercased) text
  # holds. Out of credit before a 429, so OpenAI's insufficient_quota (a
  # 429 whose message is "You exceeded your current quota…") isn't taken
  # for a throttle; Gemini says the same words of a per-minute quota, so
  # for Google they're a throttle. A bad key before a 401 sign-in.
  defp classes(provider) do
    quota = if provider == :google, do: [], else: ["exceeded your current quota"]

    [
      limit_reached: ["is used up until", "usage limit has been reached", "usage_limit_reached"],
      no_credit:
        ["credit balance is too low", "insufficient_quota", "402 (payment required)"] ++ quota,
      cost_cap: ["daily cost cap reached"],
      overloaded: ["529 (overloaded)", "overloaded_error", "overloaded"],
      invalid_key: [
        "invalid x-api-key",
        "incorrect api key",
        "invalid_api_key",
        "invalid api key",
        "api key not valid"
      ],
      sign_in_expired: ["sign-in expired", "401 (sign-in rejected)", "oauth token has expired"],
      signed_out: ["not signed in to"],
      rate_limited: [
        "429 (rate limited)",
        "rate_limit_error",
        "rate limit",
        "exceeded your current quota"
      ],
      network: ["network error"]
    ]
  end

  defp limit_reached(ctx, provider, window, text, error) do
    %{state: state, now: now} = ctx
    out = provider && exhausted(state, provider, now)
    at = until(error, out, state, provider, now)

    label =
      cond do
        out != nil and out.label != "Usage limit" -> out.label
        window != nil -> window
        true -> "usage limit"
      end

    who = if provider, do: "#{name(provider, :subscription)}'s ", else: "The "
    switch = "another model #{Rho.Config.hint(:switch_model)}."

    after_that =
      if at,
        do:
          " It resets at #{ctx.clock.(at)} (in #{Rho.Usage.duration(at - now)}). " <>
            "Until then, switch to " <> switch,
        else: " Switch to " <> switch

    %{
      kind: :limit_reached,
      title: "Usage limit reached",
      message: "#{who}#{lower_first(label)} is used up.#{after_that}",
      action: if(at, do: :wait, else: :switch_model),
      provider: provider,
      until: at,
      billing_url: nil,
      detail: text
    }
  end

  defp until({:rate_limited, %{resets_at: at}}, _out, _state, _provider, now)
       when is_integer(at) and at > now,
       do: at

  defp until(_error, %{resets_at: at}, _state, _provider, _now), do: at

  defp until(_error, nil, state, provider, now) do
    case provider && Rho.Usage.rate_limited(state, provider) do
      %{"resets_at" => at} when is_integer(at) and at > now -> at
      _ -> nil
    end
  end

  defp explanation(:no_credit, provider, _kind, _ctx, text) do
    who = if provider, do: "#{api_name(provider)} account", else: "API account"

    base(:no_credit, "Out of API credit", provider, text, %{
      message:
        "Your #{who} has run out of credit, so the model refused the call. " <>
          "Add credit on the provider's billing page, or switch to another model #{Rho.Config.hint(:switch_model)}.",
      action: :add_credit,
      billing_url: provider && billing_url(provider)
    })
  end

  defp explanation(:cost_cap, provider, _kind, _ctx, text) do
    base(:cost_cap, "Daily spending cap reached", provider, text, %{
      message:
        "Today's spending cap is reached, so no more model calls go out until tomorrow, " <>
          "or until the cap is raised.",
      action: :wait
    })
  end

  defp explanation(:overloaded, provider, _kind, _ctx, text) do
    who = if provider, do: "#{company(provider)}'s servers are", else: "The model's servers are"

    base(:overloaded, "The model is overloaded", provider, text, %{
      message:
        "#{who} too busy to answer right now; this isn't your usage. " <>
          "Try again in a minute, or switch to another model #{Rho.Config.hint(:switch_model)}.",
      action: :retry
    })
  end

  # A sign-in's 401 can read like a bad key (OpenAI says "Incorrect API key
  # provided" of a bad bearer token), and ChatGPT has no key to paste: the
  # remedy follows the credential, where it's known.
  defp explanation(:invalid_key, provider, kind, ctx, text)
       when kind == :subscription or provider == :openai_codex,
       do: explanation(:sign_in_expired, provider, :subscription, ctx, text)

  defp explanation(:invalid_key, provider, _kind, _ctx, text), do: bad_key(provider, text)

  defp explanation(:sign_in_expired, provider, :api_key, _ctx, text),
    do: bad_key(provider, text)

  defp explanation(:sign_in_expired, provider, _kind, _ctx, text) do
    who = if provider, do: "#{name(provider, :subscription)} sign-in", else: "sign-in"

    base(:sign_in_expired, "Sign-in expired", provider, text, %{
      message:
        "The #{who} has expired or was turned down. Sign in again #{Rho.Config.hint(:sign_in)}.",
      action: :sign_in
    })
  end

  defp explanation(:signed_out, provider, _kind, _ctx, text) do
    who = if provider, do: Auth.label(provider), else: "this model's provider"

    base(:signed_out, "Not signed in", provider, text, %{
      message:
        "You're not signed in to #{who}. Sign in or add a key #{Rho.Config.hint(:sign_in)}.",
      action: :sign_in
    })
  end

  # A throttle: the loop already waited it out as long as it would. rho's
  # record of the 429 may carry a far reset (Claude's unified one), which
  # isn't when a throttle lifts, so no time is promised here.
  defp explanation(:rate_limited, provider, _kind, _ctx, text) do
    who = if provider, do: company(provider), else: "The provider"

    base(:rate_limited, "Too many requests", provider, text, %{
      message: "#{who} is limiting how fast requests can be made. Wait a moment and try again.",
      action: :retry
    })
  end

  defp explanation(:network, provider, _kind, _ctx, text) do
    base(:network, "Couldn't reach the model", provider, text, %{
      message: "The connection to the model provider failed. Check the connection and try again.",
      action: :retry
    })
  end

  defp explanation(:failed, provider, _kind, _ctx, text) do
    base(:failed, "The reply failed", provider, text, %{
      message: text |> String.split("\n", parts: 2) |> hd(),
      action: :retry
    })
  end

  defp bad_key(provider, text) do
    who = if provider, do: "#{api_name(provider)} API key", else: "API key"

    base(:invalid_key, "API key rejected", provider, text, %{
      message:
        "The #{who} was turned down (revoked, mistyped, or for another account). " <>
          "Paste a working key #{Rho.Config.hint(:sign_in)}.",
      action: :add_key,
      billing_url: nil
    })
  end

  defp base(kind, title, provider, text, fields) do
    Map.merge(
      %{
        kind: kind,
        title: title,
        message: "",
        action: :retry,
        provider: provider,
        until: nil,
        billing_url: nil,
        detail: text
      },
      fields
    )
  end

  # The provider a failed call went to: the error's own, the model's, else
  # the one the text names (rho's describe uses `Rho.Auth.label/1`).
  defp provider({:signed_out, provider}, _model, _text), do: provider
  defp provider({:auth, provider, _}, _model, _text), do: provider

  defp provider({:rate_limited, %{provider: provider}}, _model, _text) when provider != nil,
    do: provider

  defp provider(_error, model, text) do
    with true <- is_binary(model), {:ok, provider} <- Auth.provider_for_model(model) do
      provider
    else
      _ -> Enum.find(Auth.providers(), &String.contains?(text, Auth.label(&1)))
    end
  end

  defp credential_kind(provider, %{} = auth) when provider != nil do
    case auth[provider] do
      %{signed_in: true, type: type} -> kind(type)
      _ -> nil
    end
  end

  defp credential_kind(_provider, _auth), do: nil

  # "Claude (Anthropic)'s 5 hours limit is used up until 05:10" → "5-hour limit".
  defp window_in(text) do
    with [before | _] <- String.split(text, " limit is used up", parts: 2),
         [_who, window] <- String.split(before, "'s ", parts: 2),
         false <- window == "usage" do
      window_label(window)
    else
      _ -> nil
    end
  end

  # ── A reply's own usage ──────────────────────────────────────────────────

  @doc """
  What a reply's model calls used, from its session entries (every
  assistant message's `usage`): tokens in, out, read from and written to
  the cache, cost in dollars (what the tokens cost at API prices; on a
  subscription the plan covers it), and one line, `"in 12.3k · out 456 ·
  cache 10.2k · $0.04"`. Nil when no call reported any tokens.
  """
  @spec reply_usage([map()]) :: reply_usage() | nil
  def reply_usage(entries) do
    c = Rho.Usage.session(entries)

    if c["input"] + c["output"] + c["cacheRead"] + c["cacheWrite"] == 0 do
      nil
    else
      cache = c["cacheRead"] + c["cacheWrite"]

      parts =
        ["in #{tokens(c["input"])}", "out #{tokens(c["output"])}"] ++
          if(cache > 0, do: ["cache #{tokens(cache)}"], else: []) ++ [money(c["cost"])]

      %{
        input: c["input"],
        output: c["output"],
        cache_read: c["cacheRead"],
        cache_write: c["cacheWrite"],
        cost: c["cost"] * 1.0,
        text: Enum.join(parts, " · ")
      }
    end
  end

  # ── Formatting ───────────────────────────────────────────────────────────

  @doc "A token count, short: `987`, `12.3k`, `4.5M`."
  @spec tokens(number()) :: String.t()
  # Where rounding would carry over (999,999 → "1000k"), the next unit.
  def tokens(n) when n >= 999_500, do: short(n / 1_000_000) <> "M"
  def tokens(n) when n >= 1_000, do: short(n / 1_000) <> "k"
  def tokens(n), do: Integer.to_string(round(n))

  # From 99.95 the one decimal would round to "100.0": whole numbers.
  defp short(x) when x >= 99.95, do: Integer.to_string(round(x))
  defp short(x), do: :erlang.float_to_binary(Float.round(x * 1.0, 1), decimals: 1)

  @doc "Dollars: `$0.00`, `<$0.01`, `$0.84`, `$12.30`."
  @spec money(number()) :: String.t()
  def money(x) when x == 0, do: "$0.00"
  def money(x) when x < 0.01, do: "<$0.01"
  def money(x), do: "$" <> :erlang.float_to_binary(x * 1.0, decimals: 2)

  @doc "A level from a percent used: `:exhausted` at 100, `:warn` from #{@warn_at}."
  @spec level(number()) :: level()
  def level(percent) when percent >= 100, do: :exhausted
  def level(percent) when percent >= @warn_at, do: :warn
  def level(_percent), do: :ok

  # ── Internals ────────────────────────────────────────────────────────────

  defp context(opts) do
    now = Keyword.get_lazy(opts, :now, fn -> System.os_time(:second) end)
    today = Keyword.get_lazy(opts, :today, &Rho.Budget.today/0)
    auth = Keyword.get_lazy(opts, :auth, &Auth.status/0)
    {now, today, auth}
  end

  defp kind(:oauth), do: :subscription
  defp kind(_api_key), do: :api_key

  defp windows(state, provider, now) do
    for {id, w} <- Rho.Usage.windows(state, provider) do
      percent = Rho.Usage.percent(w, now)
      at = if is_integer(w["resets_at"]) and w["resets_at"] > now, do: w["resets_at"]

      %{
        id: id,
        label: window_label(w["label"] || id),
        percent: percent,
        resets_at: at,
        resets_in: at && Rho.Usage.duration(at - now),
        level: level(percent)
      }
    end
  end

  defp exhausted(state, provider, now) do
    case used_up(state, provider, now) do
      %{resets_at: at, window: window} ->
        label = if window, do: window_label(window), else: "Usage limit"
        %{label: label, resets_at: at, resets_in: Rho.Usage.duration(at - now)}

      nil ->
        nil
    end
  end

  # `Rho.Usage.exhausted/3`, but a 429 with no window at 100 % counts only
  # while it is the latest word on the provider: rho never clears it, and
  # its reset can be the 5-hour window's (Claude's unified reset) even for
  # a short throttle. A later call's headers or a Refresh (a newer
  # `checked_at`) supersede it; a 429 that reported windows itself is
  # judged by them (its `at` equals their `checked_at`).
  defp used_up(state, provider, now) do
    full =
      for {_id, %{"used" => used, "resets_at" => at} = w} <- Rho.Usage.windows(state, provider),
          is_number(used) and used >= 100 and is_integer(at) and at > now,
          do: %{window: w["label"], resets_at: at}

    checked = (Rho.Usage.limits(state, provider) || %{})["checked_at"]

    case {full, Rho.Usage.rate_limited(state, provider)} do
      {[_ | _], _} ->
        Enum.max_by(full, & &1.resets_at)

      {[], %{"resets_at" => at, "at" => seen}}
      when is_integer(at) and at > now and (checked == nil or seen > checked) ->
        %{window: nil, resets_at: at}

      _ ->
        nil
    end
  end

  defp worst(levels) do
    cond do
      :exhausted in levels -> :exhausted
      :warn in levels -> :warn
      true -> :ok
    end
  end

  # rho's window labels ("5 hours", "7 days (Opus)", "1 day") as the
  # limits are known: "5-hour limit", "Weekly limit (Opus)", "1-day limit".
  defp window_label(label) do
    {span, scope} =
      case String.split(label, " (", parts: 2) do
        [span, rest] -> {span, " (" <> rest}
        [span] -> {span, ""}
      end

    span =
      case String.split(span, " ") do
        ["7", "days"] -> "Weekly"
        [n, unit] when unit in ["hour", "hours"] -> "#{n}-hour"
        [n, unit] when unit in ["day", "days"] -> "#{n}-day"
        _ -> span
      end

    "#{span} limit#{scope}"
  end

  defp lower_first("Weekly" <> rest), do: "weekly" <> rest
  defp lower_first("Usage" <> rest), do: "usage" <> rest
  defp lower_first(label), do: label

  defp models(state, provider, today) do
    days = for offset <- 0..6, do: Rho.Usage.by_model(state, Date.add(today, -offset))
    today_counts = hd(days)

    days
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.filter(&(Auth.provider_for_model(&1) == {:ok, provider}))
    |> Enum.map(fn model ->
      week = days |> Enum.map(&(&1[model] || %{})) |> Enum.reduce(%{}, &add/2)
      %{model: model, today: totals(today_counts[model] || %{}), week: totals(week)}
    end)
    |> Enum.filter(&(&1.week.requests > 0))
    |> Enum.sort_by(&{-&1.week.tokens, &1.model})
  end

  defp add(a, b), do: Map.merge(a, b, fn _k, x, y -> x + y end)

  defp sum(models, period) do
    models
    |> Enum.map(&Map.fetch!(&1, period))
    |> Enum.reduce(totals(%{}), fn t, acc -> Map.merge(acc, t, fn _k, x, y -> x + y end) end)
  end

  defp totals(c) do
    input = c["input"] || 0
    output = c["output"] || 0
    read = c["cacheRead"] || 0
    write = c["cacheWrite"] || 0

    %{
      tokens: input + output + read + write,
      input: input,
      output: output,
      cache_read: read,
      cache_write: write,
      cost: (c["cost"] || 0) * 1.0,
      requests: c["requests"] || 0,
      errors: c["errors"] || 0
    }
  end

  # The meter's and messages' names: the plan for a sign-in, the API for a key.
  defp name(:anthropic, :subscription), do: "Claude"
  defp name(:openai_codex, _kind), do: "ChatGPT"
  defp name(provider, :api_key), do: "#{api_name(provider)} API key"
  defp name(provider, _kind), do: Auth.label(provider)

  defp api_name(:anthropic), do: "Anthropic"
  defp api_name(:openai), do: "OpenAI"
  defp api_name(:openai_codex), do: "OpenAI"
  defp api_name(:google), do: "Google"

  defp company(:anthropic), do: "Anthropic"
  defp company(:openai_codex), do: "OpenAI"
  defp company(provider), do: api_name(provider)
end
