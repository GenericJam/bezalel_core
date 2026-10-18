defmodule Bezalel.Study.Sources do
  @moduledoc """
  The sources a user can switch off (`Bezalel.Study.Preferences`,
  `excluded_sources`): each ancient corpus, the editorial verdicts, each
  theologian, the notes and reference works, the ANE background and the
  method layers (Kline's Torah weave, Fee & Stuart's genre guidance).

  An excluded source's rows are left out of every result. A tool whose
  every source is excluded is withheld from the model (`withheld_tools/1`);
  a tool with content of its own besides a source (`lookup_verse` beside its
  genre guidance, `get_cross_references` beside its theme chains) is kept and
  just loses that part.

  Off by default: `editorial:verdicts` (studybible-mcp's maintainer's
  curated "Contrast" notes and links on ancient sources, the verdict
  sentences of the ⚠ notes and corpus caveats, and the Septuagint
  Apocrypha line) and `method:genre_guidance` (Fee & Stuart's genre
  guidance, an evangelical method). The factual provenance warnings
  (interpolations, emendations, editions, dates, translation caveats) are
  not a source and always stay.
  """

  alias Bezalel.Study.Ancient

  defmodule Source do
    @moduledoc "A source a user can switch off. `tools`: the tools it feeds."
    @enforce_keys [:key, :label, :group, :description, :tools]
    defstruct [:key, :label, :group, :description, tools: [], default_on: true]

    @type t :: %__MODULE__{
            key: String.t(),
            label: String.t(),
            group: String.t(),
            description: String.t(),
            tools: [String.t()],
            default_on: boolean()
          }
  end

  @ancient_tools ["search_ancient_sources", "lookup_ancient_source"]

  @theologians [
    {"heiser", "Michael S. Heiser",
     "Summaries of his papers, articles and podcast on the divine council, the sons of God, Deuteronomy 32 and the unseen realm."},
    {"bradley", "Bradley",
     "Summaries of the paper Two Fathers Only: the two households, domain transfer and binary pairs."},
    {"owen", "John Owen (1616–1683)",
     "Summaries of his works on the atonement, justification, mortification of sin, communion with God and Hebrews."},
    {"stott", "John Stott",
     "Summaries of his writing on the cross, Romans, Galatians, Ephesians, Acts and the Sermon on the Mount."},
    {"lennox", "John Lennox",
     "Summaries of his writing on Genesis 1 and science, Joseph and providence, and Daniel."},
    {"synthesis", "Synthesis notes (studybible-mcp)",
     "studybible-mcp's notes comparing views side by side (atonement models)."}
  ]

  @fixed [
    %{
      key: "editorial:verdicts",
      label: "Editorial verdicts",
      group: "Editorial",
      description:
        "studybible-mcp's curated judgements: 'Contrast' notes and links on ancient sources, " <>
          "and confessional lines in the corpus caveats (that the NT's judgement governs, " <>
          "that Philo's Logos is not the incarnate Son, that the pseudepigrapha and the " <>
          "Apocrypha are never a basis for doctrine). Factual provenance warnings are always shown.",
      tools: [],
      partial_tools: @ancient_tools ++ ["compare_biblical_versions"],
      default_on: false
    },
    %{
      key: "notes:study_notes",
      label: "Tyndale Study Notes",
      group: "Notes and reference",
      description: "Verse-level study notes (Aquifer Open Study Notes, from Tyndale).",
      tools: ["get_study_notes"]
    },
    %{
      key: "notes:translation_notes_uw",
      label: "unfoldingWord Translation Notes",
      group: "Notes and reference",
      description: "Notes for translators on wording, grammar and culture.",
      tools: ["get_study_notes"]
    },
    %{
      key: "notes:translation_notes_sil",
      label: "SIL Translator Notes",
      group: "Notes and reference",
      description: "Further translation and cultural notes for translators.",
      tools: ["get_study_notes"]
    },
    %{
      key: "notes:dictionary",
      label: "Tyndale Bible Dictionary",
      group: "Notes and reference",
      description: "Articles on people, places, customs and doctrines.",
      tools: ["get_bible_dictionary"]
    },
    %{
      key: "notes:key_terms",
      label: "FIA Key Terms",
      group: "Notes and reference",
      description: "Key biblical terms defined for translators, with their use across Scripture.",
      tools: ["get_key_terms"]
    },
    %{
      key: "crossrefs:themes",
      label: "Thematic cross-reference chains",
      group: "Notes and reference",
      description:
        "studybible-mcp's curated chains of passages for doctrinal themes (atonement, " <>
          "justification, the deity of Christ…). The verse cross-references (TSK) stay.",
      tools: [],
      partial_tools: ["get_cross_references"]
    },
    %{
      key: "ane:context",
      label: "Ancient Near East background",
      group: "Background",
      description:
        "studybible-mcp's summaries of ANE and Greco-Roman background (cosmology, temple, " <>
          "covenant, household, honour and shame…), each naming the scholars it draws on.",
      tools: ["get_ane_context"]
    },
    %{
      key: "method:torah_weave",
      label: "Torah Weave (Moshe Kline)",
      group: "Methods",
      description: "Kline's Woven Torah hypothesis: structural pairings of Torah passages.",
      tools: ["get_torah_weave"],
      partial_tools: ["lookup_verse"]
    },
    %{
      key: "method:genre_guidance",
      label: "Genre guidance (Fee & Stuart)",
      group: "Methods",
      description:
        "How to read each genre, after Fee & Stuart's How to Read the Bible for All Its " <>
          "Worth (evangelical), added to lookup_verse's passages.",
      tools: [],
      partial_tools: ["lookup_verse"],
      default_on: false
    }
  ]

  @doc "Every source, grouped for display: ancient sources, editorial, theologians, notes, background, methods."
  @spec all() :: [Source.t()]
  def all, do: Enum.map(entries(), &to_source/1)

  @doc "Every source key."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(entries(), & &1.key)

  @doc "The source `key`, or nil."
  @spec get(String.t()) :: Source.t() | nil
  def get(key), do: Enum.find(all(), &(&1.key == key))

  @doc "The keys of the sources off by default."
  @spec default_excluded() :: [String.t()]
  def default_excluded, do: for(s <- entries(), not Map.get(s, :default_on, true), do: s.key)

  @doc "Is source `key` on for `prefs`?"
  @spec enabled?(Bezalel.Study.Preferences.t(), String.t()) :: boolean()
  def enabled?(prefs, key), do: not MapSet.member?(prefs.excluded_sources, key)

  @doc """
  `:ok`, or the error a tool returns when asked for a source the user
  switched off.
  """
  @spec check(Bezalel.Study.Preferences.t(), String.t()) :: :ok | {:error, String.t()}
  def check(prefs, key) do
    if enabled?(prefs, key), do: :ok, else: {:error, excluded_message(key)}
  end

  @doc """
  `:ok`, or the error a tool returns when the user switched off every
  source it reads (`tool` among `withheld_tools/1`), naming them.
  """
  @spec check_tool(Bezalel.Study.Preferences.t(), String.t()) :: :ok | {:error, String.t()}
  def check_tool(prefs, tool) do
    keys = for source <- entries(), tool in source.tools, do: source.key

    if keys != [] and not Enum.any?(keys, &enabled?(prefs, &1)),
      do: {:error, excluded_message(keys)},
      else: :ok
  end

  @doc "The text saying source `key` (or every source in a list) is switched off."
  @spec excluded_message(String.t() | [String.t()]) :: String.t()
  def excluded_message([key]), do: excluded_message(key)

  def excluded_message(keys) when is_list(keys) do
    "The user has switched off all the sources this tool reads (" <>
      Enum.map_join(keys, ", ", &label/1) <>
      ") in Bezalel's settings, so it has nothing to return. Say so; don't supply " <>
      "them from memory."
  end

  def excluded_message(key) do
    "The user has switched off #{label(key)} in Bezalel's sources, so the tools don't " <>
      "use it. Say so; don't supply it from memory."
  end

  defp label(key), do: if(source = get(key), do: source.label, else: key)

  @doc "The excluded sources of `prefs`, in display order."
  @spec excluded(Bezalel.Study.Preferences.t()) :: [Source.t()]
  def excluded(prefs), do: Enum.reject(all(), &enabled?(prefs, &1.key))

  @doc "The tool names whose every source `prefs` excludes: the tools to withhold from the model."
  @spec withheld_tools(Bezalel.Study.Preferences.t()) :: [String.t()]
  def withheld_tools(prefs) do
    entries()
    |> Enum.flat_map(fn source -> Enum.map(source.tools, &{&1, source.key}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_tool, keys} -> Enum.all?(keys, &(not enabled?(prefs, &1))) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc "The source key of ancient corpus `corpus_key`."
  @spec ancient(String.t()) :: String.t()
  def ancient(corpus_key), do: "ancient:" <> corpus_key

  @doc "The source key of theologian `author` (`theology_content.source_author`)."
  @spec theology(String.t()) :: String.t()
  def theology(author), do: "theology:" <> author

  @doc "The theologians' author keys, as stored in the notes pack."
  @spec theology_authors() :: [String.t()]
  def theology_authors, do: Enum.map(@theologians, &elem(&1, 0))

  defp entries do
    ancient =
      for corpus <- Ancient.corpora() do
        %{
          key: ancient(corpus.key),
          label: corpus.label,
          group: "Ancient sources",
          description: works(corpus.works),
          tools: @ancient_tools
        }
      end

    theologians =
      for {author, label, description} <- @theologians do
        %{
          key: theology(author),
          label: label,
          group: "Theologians",
          description: description,
          tools: ["get_theology_context"]
        }
      end

    {editorial, rest} = Enum.split(@fixed, 1)
    ancient ++ editorial ++ theologians ++ rest
  end

  defp to_source(entry) do
    %Source{
      key: entry.key,
      label: entry.label,
      group: entry.group,
      description: entry.description,
      tools: Enum.uniq(entry.tools ++ Map.get(entry, :partial_tools, [])),
      default_on: Map.get(entry, :default_on, true)
    }
  end

  # A corpus's works: the first four titles, then how many more.
  defp works(works) do
    {shown, rest} = Enum.split(works, 4)
    titles = Enum.map_join(shown, ", ", & &1.title)
    if rest == [], do: titles <> ".", else: "#{titles} and #{length(rest)} more."
  end
end
