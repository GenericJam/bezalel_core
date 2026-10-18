defmodule Bezalel.Study.Tools do
  @moduledoc """
  The study tools (`Rho.Tool` modules), ported from
  [studybible-mcp](https://github.com/djayatillake/studybible-mcp) (MIT,
  Copyright (c) 2024 Study Bible MCP Contributors; see NOTICE) at commit
  38cef28. They read the study packs through `Bezalel.Study.DB`. Each
  module's `run/2` returns the Markdown the model reads and `result/1` the
  same answer as data for the app's screens. `run/2` hands that data to rho
  as the result's details, with the sources it rests on
  (`{:ok, {:details, markdown, %{citations: [Bezalel.Study.Citation.t()]}}}`,
  `Bezalel.Study.Citations`); every record in the Markdown has a `Source:`
  line with the same links. The live agent keeps the citations and, from
  `lookup_verse` and `word_study`, the passage card
  (`Bezalel.Agent.Details.keep_details/2`, `Bezalel.Agent.Card`).

  `all/0` is every tool, the set the live agent offers: text, lexicon,
  morphology, names, cross references, similar passages and the Torah
  weave (the core pack); people, genealogies, events and places (graph);
  study notes, dictionary, key terms, ANE and theology context and
  textual variants (notes); the Septuagint beside the Hebrew (lxx);
  Second Temple sources (ancient); and a list of research sources shipped
  with the app.

  `withheld/1` names the tools a host should not offer the model under a
  user's preferences: those whose every source the user switched off
  (`Bezalel.Study.Sources.withheld_tools/1`).

  `materials/0` are the tools that make materials rather than read the
  packs: `draw_image` (`Bezalel.Study.Tools.DrawImage`). They have no
  source to switch off; a host offers them beside `all/0` once it keeps
  materials (`Bezalel.Materials.Store`).
  """

  alias Bezalel.Study.{Sources, Tools}

  @tier1 [
    Tools.LookupVerse,
    Tools.WordStudy,
    Tools.SearchLexicon,
    Tools.SearchByStrongs,
    Tools.GetCrossReferences,
    Tools.ParseMorphology,
    Tools.LookupName,
    Tools.PeopleInPassage,
    Tools.FindSimilarPassages
  ]

  @tier2 [
    Tools.ExploreGenealogy,
    Tools.ExplorePersonEvents,
    Tools.ExplorePlace,
    Tools.FindConnection,
    Tools.GraphEnrichedSearch,
    Tools.GetStudyNotes,
    Tools.GetBibleDictionary,
    Tools.GetKeyTerms,
    Tools.GetAneContext,
    Tools.GetTheologyContext,
    Tools.GetTorahWeave,
    Tools.GetTextualVariant,
    Tools.CompareBiblicalVersions,
    Tools.SearchAncientSources,
    Tools.LookupAncientSource,
    Tools.ListResearchSources
  ]

  @doc "Every study tool module."
  @spec all() :: [module()]
  def all, do: @tier1 ++ @tier2

  @doc "The tools that make materials (`draw_image`), offered beside `all/0` by a host with a materials store."
  @spec materials() :: [module()]
  def materials, do: [Tools.DrawImage]

  @doc "The names of the tools to withhold from the model under `prefs`."
  @spec withheld(Bezalel.Study.Preferences.t()) :: [String.t()]
  def withheld(prefs), do: Sources.withheld_tools(prefs)
end
