defmodule Bezalel.Study.Tools.GetKeyTerms do
  @moduledoc """
  `get_key_terms`: FIA Key Terms entries for a theological term (the notes
  pack's BibleAquifer content).

  Ported from studybible-mcp's `handle_get_key_terms`, `get_key_terms` and
  `format_key_terms` (MIT). Same text; the pack's own absence is the pack
  error, in place of their "Aquifer data not available" message.
  `result/1` returns the entries untruncated.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Aquifer, Args}

  @impl true
  def name, do: "get_key_terms"

  @impl true
  def description do
    """
    Look up a key theological term in the FIA Key Terms database.

    Contains 200+ carefully defined theological and biblical terms with:
    - Clear definitions accessible to translators
    - Biblical usage and context
    - Cross-references to related terms
    - Translation guidance

    Relevant for a precise definition of a theological term (agape, atonement,
    justification, and similar), how a concept is used across Scripture, a
    translation-oriented explanation, or cross-references to related concepts.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "term" => %{
          "type" => "string",
          "description" =>
            "Theological term to look up (e.g., 'agape', 'atonement', 'covenant', 'grace')"
        }
      },
      "required" => ["term"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @type t :: %{term: String.t(), terms: [Aquifer.article()]}

  @doc "The entries for `args`' term (possibly none); no term is an error."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    case Args.string(args, "term") do
      "" ->
        {:error, "Please provide a term to look up."}

      term ->
        with {:ok, terms} <- Aquifer.search("key_terms", term),
             do: {:ok, %{term: term, terms: terms}}
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{term: term, terms: []}), do: "No key term found for '#{term}'."
  def render(%{terms: terms}), do: Aquifer.render(terms, 3000, "\n\n*[Term entry truncated]*")
end
