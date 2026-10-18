defmodule Bezalel.Study.Translations do
  @moduledoc """
  The English translations the study tools can quote: the NET Bible (the
  default; the translations pack, `translation_verses`) and the Berean
  Standard Bible (the core pack, `bsb_verses`). The user picks one
  (`Bezalel.Study.Preferences`, `translation`); the words and Strong's
  numbers stay STEPBible's either way.

  The NET is quoted by permission for non-commercial use
  (netbible.com/copyright): every quotation is followed by "(NET)", in
  software on the internet with "NET" linked to http://netbible.org, the
  text unaltered, and the acknowledgement (`copyright`) shown. The NET's
  translators' notes are not licensed and are not in the pack.

  `with_translation/2` runs a tool call with the translation it quotes: the
  NET with one connection to the translations pack for the whole call, or
  the BSB (with a one-line note saying why) when that pack isn't readable.
  """

  alias Bezalel.Study.DB

  @translations [
    %{
      key: "net",
      name: "NET Bible",
      abbreviation: "NET",
      url: "http://netbible.org",
      copyright:
        "Scripture quoted by permission. Quotations designated (NET) are from the NET " <>
          "Bible® copyright ©1996, 2019 by Biblical Studies Press, L.L.C. " <>
          "http://netbible.com All rights reserved.",
      licence: "Free non-commercial use by permission (netbible.com/copyright)"
    },
    %{
      key: "bsb",
      name: "Berean Standard Bible",
      abbreviation: "BSB",
      url: "https://bereanbible.com",
      copyright:
        "The Holy Bible, Berean Standard Bible, BSB is produced in cooperation with Bible " <>
          "Hub, Discovery Bible, unfoldingWord, Bible Aquifer, OpenBible.com, and the Berean " <>
          "Bible Translation Committee. This text of God's Word has been dedicated to the " <>
          "public domain.",
      licence: "Public domain"
    }
  ]

  @typedoc """
  A translation the tools can quote. Inside `with_translation/2` a
  translation from the translations pack also carries `conn`, the call's
  connection to that pack.
  """
  @type t :: %{
          required(:key) => String.t(),
          required(:name) => String.t(),
          required(:abbreviation) => String.t(),
          required(:url) => String.t(),
          required(:copyright) => String.t(),
          required(:licence) => String.t(),
          optional(:conn) => DB.conn()
        }

  @typedoc "The translation as a result carries it, for an app to draw the label and link."
  @type ref :: %{key: String.t(), abbreviation: String.t(), url: String.t()}

  @doc "Every translation, the default first."
  @spec all() :: [t()]
  def all, do: @translations

  @doc "The translation keys, the default first."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(@translations, & &1.key)

  @doc "The translation `key`, or nil."
  @spec get(term()) :: t() | nil
  def get(key), do: Enum.find(@translations, &(&1.key == key))

  @doc "`translation` as a result carries it: key, abbreviation and link."
  @spec ref(t()) :: ref()
  def ref(translation), do: Map.take(translation, [:key, :abbreviation, :url])

  @doc """
  The label after a quotation in Markdown: "[NET](http://netbible.org)" (the
  NET's terms ask for the link), "BSB".
  """
  @spec label(t() | ref()) :: String.t()
  def label(%{key: "net", abbreviation: abbreviation, url: url}), do: "[#{abbreviation}](#{url})"
  def label(%{abbreviation: abbreviation}), do: abbreviation

  @doc """
  `fun.(translation, note)` with the translation chosen by `key`, and its
  result. The NET comes from the translations pack, opened once here for
  the whole call (`translation.conn`) and closed after `fun`; without a
  readable pack, `fun` gets the BSB (core pack) and a note saying so. The
  BSB, or an unknown key, is the BSB with no note.
  """
  @spec with_translation(String.t(), (t(), String.t() | nil -> result)) :: result
        when result: term()
  def with_translation(key, fun) do
    case get(key) do
      %{key: "bsb"} = bsb ->
        fun.(bsb, nil)

      nil ->
        fun.(get("bsb"), nil)

      translation ->
        case DB.with_pack(:translations, &fun.(Map.put(translation, :conn, &1), nil)) do
          {:ok, result} -> result
          {:error, _} -> fun.(get("bsb"), missing(translation))
        end
    end
  end

  defp missing(translation) do
    "The #{translation.name} isn't on this device (the translations pack isn't " <>
      "downloaded), so this English is the BSB."
  end
end
