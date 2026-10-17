defmodule Bezalel.Study.Tools.ParseMorphology do
  @moduledoc """
  `parse_morphology`: a grammatical parsing code explained.

  Ported from studybible-mcp's `handle_parse_morphology` (MIT); same text.
  `result/1` returns the morphology row.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, DB, Format}

  @fields [
    {"person", "Person"},
    {"number", "Number"},
    {"tense", "Tense"},
    {"voice", "Voice"},
    {"mood", "Mood"},
    {"case_value", "Case"},
    {"gender", "Gender"}
  ]

  @impl true
  def name, do: "parse_morphology"

  @impl true
  def description do
    """
    Explain a morphological/grammatical parsing code.

    For Greek: Robinson codes (e.g., 'V-AAI-3S' = Verb, Aorist, Active, Indicative, 3rd person, Singular)
    For Hebrew: STEPBible's codes as lookup_verse shows them (e.g., 'HVqp3ms' = Hebrew Verb, Qal, Perfect, 3rd person, masculine, singular)

    Returns full grammatical explanation including part of speech,
    person, number, tense, voice, mood, case, and gender where applicable.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "code" => %{
          "type" => "string",
          "description" => "Morphology code to parse (e.g., 'V-AAI-3S', 'N-GSF', 'HVqp3ms')"
        },
        "language" => %{
          "type" => "string",
          "enum" => ["greek", "hebrew"],
          "description" => "Language of the code. Default: greek"
        }
      },
      "required" => ["code"]
    }
  end

  @impl true
  def run(args, _ctx) do
    with {:ok, result} <- result(args), do: {:ok, render(result)}
  end

  @typedoc "The code as given and its morphology row."
  @type t :: %{code: String.t(), parsing: DB.row()}

  @doc "The parsing of `args`' code; an unknown code is an error."
  @spec result(map()) :: {:ok, t()} | {:error, String.t()}
  def result(args) do
    code = Args.string(args, "code")
    language = String.downcase(Args.optional(args, "language") || "greek")

    if code == "" do
      {:error, "Please provide a morphology code to parse."}
    else
      sql = "SELECT * FROM morphology WHERE code = ? AND language = ?"

      case DB.with_pack(:core, &DB.one(&1, sql, [code, language])) do
        {:ok, nil} -> {:error, "Unknown morphology code: #{code}"}
        {:ok, parsing} -> {:ok, %{code: code, parsing: parsing}}
        error -> error
      end
    end
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(%{code: code, parsing: parsing}) do
    fields =
      for {key, label} <- @fields, Format.present?(parsing[key]), into: "" do
        "**#{label}**: #{parsing[key]}\n"
      end

    "## Morphology: #{code}\n\n" <>
      "**Language**: #{Format.title(Format.s(parsing["language"]))}\n" <>
      "**Part of Speech**: #{Format.s(parsing["part_of_speech"])}\n" <>
      fields <> "\n**Full Parsing**: #{Format.s(parsing["parsing"])}\n"
  end
end
