defmodule Bezalel.Agent.Details do
  @moduledoc """
  What every Bezalel app's agent loop shares with rho: the part of a study
  tool's details kept in the session (`keep_details/2`, the loop's
  `:keep_details`), and reading it back (`kept_card/1`, `kept_citations/1`).

  A tool's details (`{:details, markdown, result}`, `Rho.ToolRunner`) are
  its data for the screens; the session keeps
  `%{"card" => card, "citations" => [citation map]}`: the passage card
  (`Bezalel.Agent.Card`, from `lookup_verse` and `word_study`) and the
  sources the result rests on (`Bezalel.Study.Citation.to_map/1`), either
  left out when there is none. Sessions written before citations kept the
  bare card as the details; the readers take both.
  """

  alias Bezalel.Agent.Card
  alias Bezalel.Study.Citation

  @doc """
  The part of tool `name`'s `details` to keep in the session (JSON-safe), or
  nil when there is nothing to keep. The host passes it to `Rho.Loop` as
  `keep_details: &Bezalel.Agent.Details.keep_details/2`.
  """
  @spec keep_details(String.t(), term()) :: map() | nil
  def keep_details(name, details) do
    citations =
      case details do
        %{citations: [_ | _] = citations} -> Enum.map(citations, &Citation.to_map/1)
        _ -> []
      end

    kept =
      %{"card" => Card.from_tool(name, details), "citations" => citations}
      |> Map.reject(fn {_k, v} -> v in [nil, []] end)

    if kept == %{}, do: nil, else: kept
  end

  @doc "The passage card in a toolResult's stored `details` (either shape), or nil."
  @spec kept_card(term()) :: Card.t() | nil
  def kept_card(%{"citations" => _} = kept), do: kept["card"]
  def kept_card(%{"card" => card}), do: card
  def kept_card(%{"verses" => _} = card), do: card
  def kept_card(_details), do: nil

  @doc "The citations in a toolResult's stored `details`: none in the old shape (a bare card)."
  @spec kept_citations(term()) :: [Citation.t()]
  def kept_citations(%{"citations" => citations}) when is_list(citations),
    do: for(map <- citations, c = Citation.from_map(map), do: c)

  def kept_citations(_details), do: []
end
