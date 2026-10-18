# Study tools

Bezalel's study tools are [studybible-mcp](https://github.com/djayatillake/studybible-mcp)'s
query layer ported to Elixir (MIT, commit `38cef28`; see [NOTICE](../NOTICE)), run as
[rho](https://github.com/GenericJam/rho) tool modules with no MCP layer. They read the
study packs the phone app builds and publishes (its `data/README.md`,
[GenericJam/bezalel_mob](https://github.com/GenericJam/bezalel_mob)). They live here, in
bezalel_core, so the phone app and the website (bezalel_ca) run the same tools.

## Modules

| Module | What |
|---|---|
| `Bezalel.Study.Tools` | `all/0`, every tool module (what the live agent offers) |
| `Bezalel.Study.Tools.*` | One module per tool, named after it (`LookupVerse` is `lookup_verse`): tier 1 `LookupVerse`, `WordStudy`, `SearchLexicon`, `SearchByStrongs`, `GetCrossReferences`, `ParseMorphology`, `LookupName`, `PeopleInPassage`, `FindSimilarPassages`; tier 2 `ExploreGenealogy`, `ExplorePersonEvents`, `ExplorePlace`, `FindConnection`, `GraphEnrichedSearch` (graph), `GetStudyNotes`, `GetBibleDictionary`, `GetKeyTerms`, `GetAneContext`, `GetTheologyContext`, `GetTextualVariant` (notes), `GetTorahWeave` (core), `CompareBiblicalVersions` (lxx and core), `SearchAncientSources`, `LookupAncientSource` (ancient), `ListResearchSources` (no pack). Each is a `Rho.Tool` (`run/2` → the Markdown the model reads) with `result/1` (the same answer as data for the screens, e.g. `lookup_verse`'s words with their Strong's numbers, `explore_genealogy`'s tree as nodes linked to the next generation, `explore_person_events`'s timeline, `find_connection`'s path as steps) and `render/1`. `LookupVerse` and `WordStudy`'s `run/2` also hand `result/1` to rho as the result's details (`{:ok, {:details, markdown, result}}`): the model gets the Markdown, the screen the data, which `Bezalel.Agent.Card` makes the passage card. The Mermaid diagrams of the graph tools stay in the Markdown only |
| `Bezalel.Study.DB` | Opens the packs read-only |
| `Bezalel.Study.Reference` | Book names and reference forms ("Ex 31:2-3", "Exodus 31", "Jn 3:16", "Jude 3") |
| `Bezalel.Study.Verses`, `Bezalel.Study.Lexicon` | Verse and lexicon queries |
| `Bezalel.Study.Format` | Shared Markdown (verses, lexicon entries) |
| `Bezalel.Study.Hermeneutics` | Genres and their guidance (Fee & Stuart) |
| `Bezalel.Study.Prompt` | The system prompt |
| `Bezalel.Study.Args`, `Bezalel.Study.Patterns` | Argument reading; the regexes, compiled at run time (mob_dev rule) |
| `Bezalel.Study.Graph` | Person lookup, family and Mermaid helpers shared by the graph tools |
| `Bezalel.Study.Aquifer` | Dictionary and key-term search and article Markdown |
| `Bezalel.Study.Ancient`, `Bezalel.Study.Ancient.Passages`, `Bezalel.Study.Ancient.Registry` | Ancient-source citations, search folding and excerpts, and their corpus registry (6 corpora, 109 works) as data |

## Pack access

`Bezalel.Study.DB.with_pack/2` opens the one pack a call needs, read-only, with Exqlite
directly, and closes it when the call ends. The directory is the host app's to name:
`config :bezalel_core, :packs_dir`, a path or `{module, function, args}` returning one,
resolved on every call (tests here: `test/fixtures/packs`). The phone app names
`Bezalel.Packs.Storage.packs_dir/0`: `packs` under `Mob.Storage.dir(:app_support)` (iOS
Library/Application Support, excluded from iCloud backup; Android `files`), where
`Bezalel.Packs` downloads them (verified, swapped in whole; its `data/README.md`).

Why not a second Ecto repo with the packs `ATTACH`ed: rho runs a reply's tool calls in
parallel, and a connection per call shares nothing between them, while a pool would hold
connections open across pack downloads (a new or replaced pack would need the repo
restarted, and `ATTACH` on every pooled connection for whichever packs exist). The tools
run fixed SQL on a fixed schema, so Ecto adds nothing. Opening a pack costs about a
millisecond on a Mac, beside a model round trip. A missing pack is an error result that
names it ("The graph study pack (people, places and events) isn't downloaded on this
device…"); a file that isn't a readable pack (a broken download) is an error too.

Tools that read two packs (`graph_enriched_search`: graph then core; `compare_biblical_versions`:
lxx then core for the Masoretic side; `lookup_verse`: core then notes for its
textual-variant and quotation hints) make two `with_pack/2` calls rather than `ATTACH`
the second pack: the queries never join across packs (each side is a separate lookup),
so `ATTACH` would save nothing but a millisecond, and two calls keep each pack's
missing-pack handling separate. `lookup_verse` without the notes pack leaves those
hints out and answers as before; `compare_biblical_versions` without lxx still gives an
MT-only comparison in canonical numbering, as theirs did without the LXX table.

`list_research_sources` reads studybible-mcp's own catalogue
(`src/study_bible_mcp/research_sources.json` at the pin, MIT), copied to
`priv/study/research_sources.json` and read at compile time, so it needs no pack.

### Full-text search on the phone

The ancient pack's `ancient_source_passages_fts` is an FTS5 table. The host exqlite
build has FTS5 (its Makefile sets `-DSQLITE_ENABLE_FTS5=1`). Before mob_dev 0.7.29 /
mob_new 0.6.13 (MOB-487) the phone's NIF was built from the same `sqlite3.c` with only
`-DSQLITE_THREADSAFE=1`, so phones had no FTS5. Since MOB-487 the device builds take
exqlite's defines, FTS5 included (the phone app's `android/app/src/main/jni/build.zig`
and `CMakeLists.txt` carry the list; the iOS builds are mob_dev's). Not yet confirmed by
a search on a device. `search_ancient_sources` still checks for FTS5 and returns an
error saying so on a SQLite without it (and that `lookup_ancient_source`, which doesn't
use FTS, still works), so a host app built some other way degrades the same way.

## Errors and empty results

studybible-mcp returns everything as text. Here, input the tool can't act on (no
reference, an unreadable one, an unknown book, chapter, verse, Strong's number or
morphology code, a bad `limit`) and a missing pack are `{:error, text}`, so rho marks the
result as an error; a search that finds nothing is `{:ok, text}`. The texts are
studybible-mcp's.

## Differences from studybible-mcp's output

Checked by running both on the same data (their handlers on the packs merged into one
database). Tier 1: 53 calls across the nine tools; `find_similar_passages` matched
exactly once their handler was given the precomputed neighbours. Tier 2: 50 calls on
the graph tools, 78 on the notes tools, 80 on `get_torah_weave`, `get_textual_variant`,
`compare_biblical_versions` and `lookup_verse` passages with hints, 85 on the ancient
tools (FTS queries with quotes, operators, brackets and NEAR included): 290 of 293
identical; the three that differ are the `get_theology_context` and
`list_research_sources` items below. Every difference is one listed here.

- `lookup_verse`: the cross-reference hint names only the TSK (no Harrison/Römhild or
  Burnett wording, no Gage/Bradley John↔Revelation aside). Their verse-table-missing
  message is gone (a missing core pack is the pack error). Without the notes pack, the
  textual-variant and NT↔OT quotation hints are left out; the Torah weave hint (core)
  stays.
- `get_cross_references`: the core pack's only dataset is the Treasury of Scripture
  Knowledge (Harrison/Romhild isn't built; Gage/Bradley and Burnett are excluded), so the
  description, the `source` enum and the legend name only the TSK. The ranking is theirs
  restricted to TSK (votes, then target). Another `source` is an error.
- `find_similar_passages`: reads `similar_passages` (20 per verse, BGE-small vectors of
  the BSB) instead of sqlite-vec, so at most 20 results and no extension messages; the
  examples in the description are ones the packs give. "No similar passages" says the
  verse may not be in the database (every verse has neighbours).
- `lookup_name`: a relationship with several names prints "Cain, Abel, Seth" where Python
  printed "['Cain', 'Abel', 'Seth']".
- `people_in_passage`, `graph_enriched_search`: an entity without a name shows its id
  instead of "None".
- `explore_genealogy`: a `direction` other than ancestors, descendants or both is an
  error (theirs said "No genealogical data"); a null `direction` is both, and a null or
  non-numeric `generations` the default 5 (theirs traced nothing, or for text every
  generation).
- `graph_enriched_search` keeps theirs: each person's family is looked up by name, so a
  namesake can stand in; an unreadable reference gives the heading and "No entity data".
- Their "… data not available" messages (graph, Aquifer, ANE, theology, Torah Weave,
  textual variants, Septuagint) are the missing-pack error.
- `get_study_notes`: a reference naming no verse or chapter of the 66 books is an error.
  `get_ane_context`: an unreadable reference, or a dimension or period outside the enum,
  is an error. `get_theology_context`: an unknown theme or author, or a reference without
  a verse, is an error; the unknown-author text drops "Run the import script first.",
  and a chapter that isn't a number ("a.b") is the not-found error where theirs printed
  a Python exception.
- `get_torah_weave`: a reference that isn't a verse of Genesis–Deuteronomy is an error; a
  Torah verse no cell covers is not.
- `get_textual_variant`: an empty reference or one that isn't a single verse is an
  error; a verse with nothing catalogued is not.
- `compare_biblical_versions`: empty, unreadable, New Testament or unsupported
  references, bad `versions` or `numbering`, and MT-only for an LXX-only book are
  errors; "No … text found" is not.
- `search_ancient_sources`, `lookup_ancient_source`: a null `corpus` or `period` is the
  default (theirs rejected a null corpus); a corpus missing from the pack is an error
  without their "run upgrade_database.py" advice; case folding is `String.downcase/1`
  plus Python `casefold`'s special cases (final sigma, ß, ſ, Greek symbol forms, fi/fl);
  without FTS5 the search is an error (above). Errors (empty or unreadable query, bad
  corpus, period, limit or reference; unknown, ambiguous or unreadable citation) are
  `{:error, text}`; no match, no link and out of range are not.
- A missing column value prints as nothing rather than "None".
- Genre of a written-out reference ("John 3:16") uses the full book-name table, not
  hermeneutics.py's shorter one, so more abbreviations get a genre line.
- A `limit` of zero, a negative number or text is the default (theirs passed it to SQL,
  where -1 meant no limit), except `lookup_name`, which keeps their error for a limit
  outside 1–20, and the ancient tools, which keep their limit errors. A fractional limit
  is refused or the default (Python truncated 2.5 to 2; `list_research_sources` gives its
  default 4). A number outside SQLite's 64-bit range is treated as unreadable. String
  arguments are trimmed (so " Hebron " finds Hebron).
- References, Strong's numbers and ancient-source locators take ASCII digits only ("Ps
  22:18", "G26", not other scripts' numerals), where their `\d` and `isdigit` accepted any
  Unicode digit.
- Descriptions are theirs, except `parse_morphology` (it describes the Hebrew codes the
  packs use, STEPBible's, e.g. 'HVqp3ms'), `get_cross_references` (TSK only) and
  `find_similar_passages` (at most 20, examples the packs give).
- Known gap (also in tier 1): a name or topic over about 50 KB makes SQLite refuse the
  `LIKE` pattern, and the tool crashes (rho reports "Tool crashed") instead of
  returning an error.

## The system prompt

From their `prompts/system_prompt.md` and `hermeneutics.py`. Kept: the Fee & Stuart
principles, the seven-step reasoning pattern, the genre table (generated from
`Bezalel.Study.Hermeneutics`), the original-language format, the interpretation errors,
"when you don't know" and humility. Added: Bezalel's role (a sermon-prep companion for
pastors), and ground rules: look passages up and cite them; keep text and interpretation
apart; say what a tool returned versus what is inference; report tool errors and missing
packs instead of filling in from memory. The tool guidance covers all 25 tools.

Left out: the "Reading Scripture in its ancient context" section (populated divine realm,
derivation hierarchy, hourglass narrative, 1 Enoch, "recovery not novelty") and their
guidance for integrating ANE context. These present one school's framework (largely
Heiser's) as the default reading. A general study companion for pastors of different
traditions should not take a side there by default. In their place, a "Background
scholarship" section covers `get_ane_context`, `get_theology_context`, the ancient
sources and `list_research_sources` as background with their sources and authors named
(Walton, Milgrom, King and Stager, deSilva, Heiser, Rillera for ANE entries; Heiser,
Bradley, Stott, Owen, Lennox for theology), each one voice among several, attributed
and set beside other readings, never the frame of the answer. `get_torah_weave` is
presented as Kline's hypothesis, `get_textual_variant` as evidence before conclusions.
The translation-shift point (check *nephesh*, *ruach* in their Hebrew range) stays, as a
word-study habit.

Formatting for a phone (added for Bezalel): the reader sees a column about 40
characters wide, so tables are limited to three short columns and anything wider becomes
a list; no unwrappable long lines. The Markdown renderer can wrap a wide table only
badly, so the model is asked not to write one.

## Tests and fixtures

The phone app's `data/scripts/make_fixtures.py` cuts a small copy of each pack from its
`data/out` into this repository's `test/fixtures/packs` (it writes to
`../bezalel_core/test/fixtures/packs` by default: Genesis 1–2, Exodus 31, Psalm 22,
John 3, Jude, plus the verses, people, places, articles, ANE entries, theology content
and ancient passages the tests name; about 6 MB in all; its docstring lists what each
table keeps; `--pack <name>` cuts one). Tests in `test/bezalel/study/` run against
those, never the real packs; they port studybible-mcp's handler tests (and its
theology, research-sources, broad-entry, textual-variant, biblical-versions and
ancient-corpus tests) and add the Exodus 31 cases. The phone app's tests read the same
fixtures from this dependency. In the phone app, `mix run --no-start
scripts/study_tools_smoke.exs` runs every tool in `Tools.all/0` against the real packs
and fails if one errors or is left out.
