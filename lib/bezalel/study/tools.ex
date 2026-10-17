defmodule Bezalel.Study.Tools do
  @moduledoc """
  The study tools (`Rho.Tool` modules), ported from
  [studybible-mcp](https://github.com/djayatillake/studybible-mcp) (MIT,
  Copyright (c) 2024 Study Bible MCP Contributors; see NOTICE) at commit
  38cef28. They read the study packs through `Bezalel.Study.DB`. Each
  module's `run/2` returns the Markdown the model reads and `result/1` the
  same answer as data for the app's screens. `lookup_verse` and
  `word_study`'s `run/2` hand that data to rho as the result's details
  (`{:ok, {:details, markdown, result}}`), which the live agent turns into
  the passage card (`Bezalel.Agent.Card`).

  `all/0` is every tool, the set the live agent offers: text, lexicon,
  morphology, names, cross references, similar passages and the Torah
  weave (the core pack); people, genealogies, events and places (graph);
  study notes, dictionary, key terms, ANE and theology context and
  textual variants (notes); the Septuagint beside the Hebrew (lxx);
  Second Temple sources (ancient); and a list of research sources shipped
  with the app.
  """

  alias Bezalel.Study.Tools

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
end
