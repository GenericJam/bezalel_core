defmodule Bezalel.Study.Preferences do
  @moduledoc """
  A user's study settings, which the tools and the system prompt follow:

    * `approach`: the user's own text for the editable part of the system
      prompt (persona, audience, hermeneutics, answer style); nil is
      `Bezalel.Study.Prompt.default_approach/0`;
    * `scripture_labels`: whether results label the canon status of
      non-biblical sources (by tradition where traditions differ);
    * `excluded_sources`: `Bezalel.Study.Sources` keys switched off
      (default: the editorial verdicts and the genre guidance);
    * `limit`: how many results a list tool returns when the model doesn't
      say (each tool still caps it at its own maximum);
    * `translation`: the English the tools quote (`Bezalel.Study.Translations`).

  Settings live in the host app. `current/1` asks it through `config
  :bezalel_core, :preferences, {module, function, args}`, called with the
  tool's ctx appended (it carries `:session_id`, so a host serving several
  users can find whose session it is); unset, everything is the default.
  """

  alias Bezalel.Study.{Sources, Translations}

  defstruct approach: nil,
            scripture_labels: true,
            excluded_sources: MapSet.new(["editorial:verdicts", "method:genre_guidance"]),
            limit: 8,
            translation: "net"

  @type t :: %__MODULE__{
          approach: String.t() | nil,
          scripture_labels: boolean(),
          excluded_sources: MapSet.t(String.t()),
          limit: pos_integer(),
          translation: String.t()
        }

  @max_limit 50

  @doc """
  Settings from a map or keyword list (atom or string keys), or a struct to
  re-check. Unknown keys are ignored; an invalid value is the default: an
  approach that isn't non-blank text, a limit outside 1–#{@max_limit}, a
  translation not in `Bezalel.Study.Translations.keys/0`. Unknown source
  keys are dropped from `excluded_sources`.
  """
  @spec new(t() | map() | keyword()) :: t()
  def new(%__MODULE__{} = prefs), do: prefs |> Map.from_struct() |> new()
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    defaults = %__MODULE__{}

    %__MODULE__{
      approach: approach(fetch(opts, :approach)),
      scripture_labels:
        valid(fetch(opts, :scripture_labels), &is_boolean/1, defaults.scripture_labels),
      excluded_sources: excluded(fetch(opts, :excluded_sources), defaults.excluded_sources),
      limit:
        valid(fetch(opts, :limit), &(is_integer(&1) and &1 in 1..@max_limit), defaults.limit),
      translation:
        valid(fetch(opts, :translation), &(&1 in Translations.keys()), defaults.translation)
    }
  end

  @doc """
  The settings for a tool call with `ctx` (the `Rho.Tool` ctx), from the
  host's `config :bezalel_core, :preferences, {m, f, a}` (`apply(m, f, a ++
  [ctx])`, returning a struct or a map, normalised by `new/1`); the
  defaults when unset.
  """
  @spec current(map()) :: t()
  def current(ctx \\ %{}) do
    case Application.get_env(:bezalel_core, :preferences) do
      {module, function, args} -> new(apply(module, function, args ++ [ctx]) || %{})
      _unset -> %__MODULE__{}
    end
  end

  @doc "The default result count of a list tool whose maximum is `max`."
  @spec limit(t(), pos_integer() | nil) :: pos_integer()
  def limit(prefs, nil), do: prefs.limit
  def limit(prefs, max), do: min(prefs.limit, max)

  defp fetch(opts, key) do
    case Map.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(opts, Atom.to_string(key))
    end
  end

  defp valid({:ok, value}, check, default), do: if(check.(value), do: value, else: default)
  defp valid(:error, _check, default), do: default

  defp approach({:ok, text}) when is_binary(text),
    do: if(String.trim(text) == "", do: nil, else: text)

  defp approach(_), do: nil

  defp excluded({:ok, keys}, _default) when is_list(keys) or is_struct(keys, MapSet) do
    known = MapSet.new(Sources.keys())
    keys |> Enum.filter(&(is_binary(&1) and MapSet.member?(known, &1))) |> MapSet.new()
  end

  defp excluded(_invalid, default), do: default
end
