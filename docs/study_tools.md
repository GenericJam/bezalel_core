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
| `Bezalel.Study.Tools` | `all/0`, every study tool module; `materials/0`, the tools that make materials (`draw_image`); `withheld/1`, the tool names to withhold under a user's preferences |
| `Bezalel.Study.Tools.DrawImage` | `draw_image`: a picture drawn by the image model the user chose ("Pictures by": OpenAI's gpt-image or a Gemini image model, `models/0`) on that provider's API key, kept as a material, returned by reference ([Materials](#materials-drawings-and-read-aloud)) |
| `Bezalel.Study.Tools.*` | One module per tool, named after it (`LookupVerse` is `lookup_verse`): tier 1 `LookupVerse`, `WordStudy`, `SearchLexicon`, `SearchByStrongs`, `GetCrossReferences`, `ParseMorphology`, `LookupName`, `PeopleInPassage`, `FindSimilarPassages`; tier 2 `ExploreGenealogy`, `ExplorePersonEvents`, `ExplorePlace`, `FindConnection`, `GraphEnrichedSearch` (graph), `GetStudyNotes`, `GetBibleDictionary`, `GetKeyTerms`, `GetAneContext`, `GetTheologyContext`, `GetTextualVariant` (notes), `GetTorahWeave` (core), `CompareBiblicalVersions` (lxx and core, scrolls for its DSS witnesses), `SearchAncientSources`, `LookupAncientSource` (ancient, and scrolls for most Qumran works), `ListResearchSources` (no pack). Each is a `Rho.Tool` (`run/2` → the Markdown the model reads) with `result/1` (the same answer as data for the screens, e.g. `lookup_verse`'s words with their Strong's numbers, `explore_genealogy`'s tree as nodes linked to the next generation, `explore_person_events`'s timeline, `find_connection`'s path as steps) and `render/1`. Every `run/2` hands rho the data with its `citations` as the result's details (`{:ok, {:details, markdown, data}}`, [Sources](#sources)): the model gets the Markdown, the screen the data, which `Bezalel.Agent.Card` makes the passage card for `lookup_verse` and `word_study`. The Mermaid diagrams of the graph tools stay in the Markdown only |
| `Bezalel.Study.DB` | Opens the packs read-only (`core`, `notes`, `lxx`, `ancient`, `graph`, `translations`, `scrolls`, `fathers`) |
| `Bezalel.Study.Preferences` | A user's settings: approach, scripture labels, excluded sources, default result count, translation, image model, pushback model; `current/1` asks the host |
| `Bezalel.Study.Sources` | The sources a user can switch off, and the tools withheld when all of a tool's sources are off |
| `Bezalel.Study.Translations` | The English translations the tools quote (NET, BSB) with their labels, links and acknowledgements |
| `Bezalel.Study.Reference` | Book names and reference forms ("Ex 31:2-3", "Exodus 31", "Jn 3:16", "Jude 3"); `book_name/1`, a code's English name |
| `Bezalel.Materials`, `Bezalel.Materials.Material`, `Bezalel.Materials.Store` | Materials: the record, content addressing and file layout, derivatives, what goes to the model, rho's attachment resolver, the host's store ([Materials](#materials-drawings-and-read-aloud)) |
| `Bezalel.Speech` | A reply's summary as words for text-to-speech |
| `Bezalel.Study.Verses`, `Bezalel.Study.Lexicon` | Verse and lexicon queries |
| `Bezalel.Study.Format` | Shared Markdown (verses, lexicon entries) |
| `Bezalel.Study.Hermeneutics` | Genres and their guidance (Fee & Stuart) |
| `Bezalel.Study.Prompt` | The system prompt: `fixed/1`, `default_approach/0`, `other_models/0`, `system_prompt/2` |
| `Bezalel.Study.Args`, `Bezalel.Study.Patterns` | Argument reading; the regexes, compiled at run time (mob_dev rule) |
| `Bezalel.Study.Graph` | Person lookup, family and Mermaid helpers shared by the graph tools |
| `Bezalel.Study.Aquifer` | Dictionary and key-term search and article Markdown |
| `Bezalel.Study.Ancient`, `Bezalel.Study.Ancient.Passages`, `Bezalel.Study.Ancient.Registry`, `Bezalel.Study.Ancient.Scrolls`, `Bezalel.Study.Ancient.Fathers` | Ancient-source citations (with the scrolls pack's fragment locators), search folding and excerpts, and their corpus registry (7 corpora, 259 works, 132 of them Dead Sea Scrolls manuscripts, 18 the Apostolic Fathers) as data |
| `Bezalel.Study.BiblicalScrolls` | The biblical Dead Sea Scrolls' readings by verse (scrolls pack) |
| `Bezalel.Study.Citation`, `Bezalel.Study.Citations` | A source a result rests on, and every URL template that builds one ([Sources](#sources)) |
| `Bezalel.Agent.Details`, `Bezalel.Agent.Reply`, `Bezalel.Agent.Card` | What the session keeps of a tool's data (`keep_details/2`, `kept_card/1`, `kept_citations/1`), a reply's fold and sources, the passage card |
| `Bezalel.Agent.Pushback` | Another model pushes back on a reply and the lead answers it: the critic's brief, one round per reply, automatic or on demand ([Pushback](#pushback-another-model-reviews-a-reply)) |

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

The tools that quote English verses read the NET from the translations pack, opened
once per tool call: `Translations.with_translation/2` opens it (which also checks it is
readable) and hands the call's queries its connection (`translation.conn`, used by
`Verses.attach_english/3`); without it the tools quote the BSB from core and say so
(see Translation below).

`list_research_sources` reads studybible-mcp's own catalogue
(`src/study_bible_mcp/research_sources.json` at the pin, MIT), copied to
`priv/study/research_sources.json` and read at compile time, so it needs no pack.

### The Dead Sea Scrolls (scrolls pack)

The scrolls pack is built here, by `data/`'s `mix bezalel.data.scrolls` from
ETCBC/dss (the Abegg–Bowley–Cook transcription, CC BY-NC 4.0), in two parts
(`data/README.md`; why these works and these choices:
[decisions/2026-10-18-dead-sea-scrolls-pack.md](../decisions/2026-10-18-dead-sea-scrolls-pack.md)):

- **Major non-biblical works**: 30 compositions in 132 Qumran manuscripts
  (`Bezalel.Study.Ancient.Scrolls`), in the ancient pack's own tables, so the
  ancient tools read them with the same SQL, folding and excerpts; they are
  works of the `qumran` corpus beside CD, 1QS, 1QSa and 1QpHab (which stay in
  the ancient pack). Each manuscript is a work cited by its siglum or
  conventional name ('4Q174', '4QFlor'), the copies of one composition
  collected under its title ('Songs of the Sabbath Sacrifice 4Q405 …'), never
  merged into a composite. A passage is one fragment or column as ETCBC labels
  it; the locator is that label and a line ('1QM 5:3', '11QMelch ii 18',
  '4Q174 frg. 1–2 i 10'), resolved against the pack: `Ancient.parse_fragment/1`
  reads the citation, `Ancient.fragment_keys/1` the keys to look the label up
  by (`section_number`), and the label's position (`book_number`) × 1000 + the
  line is the sort key the overlap query uses. `search_ancient_sources` over
  `qumran` or `all` searches both packs and ranks a stage's rows together;
  without the scrolls pack (or with one whose tables can't be read,
  `DB.check_tables/3`) it searches the ancient pack and says what it left
  out, and `lookup_ancient_source` of a scrolls work is the missing- or
  damaged-pack error.
- **Biblical manuscripts**: every verse of the Hebrew Bible ETCBC assigns to
  a word of a biblical scroll, per manuscript (265 sigla, 11,919 readings of
  8,020 verses in 36 books; `dss_biblical_verses`), with the fragment and line
  locator, the text with its brackets, and how many letters survive outside
  `[ ]`. `compare_biblical_versions` shows them as `DSS` witnesses beside the
  MT and LXX (default on, source `manuscripts:dss`): the tool already groups
  witnesses by canonical verse with each edition's own numbering, which is
  what a reading of 4QDeutj at Deuteronomy 32:8 is; `get_textual_variant`
  stays Heiser's curated cases. A reading wholly inside `[ ]` says that
  nothing legible survives; ETCBC's Hebrew numbering is mapped to the packs'
  English one and named ('Hebrew numbering Psa.22.17').

### The Apostolic Fathers (fathers pack)

The fathers pack is built here, by `data/`'s `mix bezalel.data.fathers` (why these
sources, the numbering, dates and labels:
[decisions/2026-10-22-apostolic-fathers-pack.md](../decisions/2026-10-22-apostolic-fathers-pack.md)):
Lake's Greek (and the Latin where only a Latin version survives) as corrected by James
Tauber and Seumas Macdonald (*Open Apostolic Fathers* 1.0), with CAFE's English, a
machine translation (GPT-4o's first drafts, published without systematic human
revision), both CC BY-SA 4.0, one passage per verse in the ancient pack's own tables.
The `apostolic_fathers` corpus (`Bezalel.Study.Ancient.Fathers`, appended to the
registry, every work `pack: :fathers`) has 18 works: 1–2 Clement, Ignatius' seven
letters, Polycarp To the Philippians, the Martyrdom of Polycarp and its Moscow epilogue,
the Didache, Barnabas, the Shepherd of Hermas as Visions, Mandates and Similitudes
(book.chapter.verse: 'Hermas, Vision 1.1.1', 'Mandate 4.1.1') and Diognetus; no
Papias or Quadratus (not in the source). Each tag dates the work as a scholarly range
with its source (Ehrman's Loeb introductions), tier `A/B` for 1 Clement and the
Didache, `B` for the rest; the status is "Not Scripture", naming the codices that
copied a work after Revelation (Alexandrinus: 1–2 Clement; Sinaiticus: Barnabas,
Hermas). The English is labelled a machine translation wherever it is shown: the tag
("CAFE machine-translated English"), the corpus caveat, the sources line, and each
passage's citation (`Citation.translation` `:machine`, whose Source line tells the
model to say so). `search_ancient_sources` reads every pack holding a work of the
corpora in scope (ancient, scrolls, fathers); a pack in scope that is missing or
can't be read is left out with a note naming what that left unsearched, and a search
of `apostolic_fathers` alone, or a citation of one of its works, is the missing-pack
error.

### Full-text search on the phone

The ancient pack's `ancient_source_passages_fts` is an FTS5 table (the scrolls pack's too). The host exqlite
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
  is refused or the default (Python truncated 2.5 to 2). The default itself is the
  user's setting (`Preferences`, `limit`, 8 unless changed; theirs was 4), held to each
  tool's maximum (`lookup_name` and `search_ancient_sources` 20, `find_similar_passages`
  20, `lookup_ancient_source` and `list_research_sources` 10). A number outside SQLite's
  64-bit range is treated as unreadable. String arguments are trimmed (so " Hebron "
  finds Hebron).
- References, Strong's numbers and ancient-source locators take ASCII digits only ("Ps
  22:18", "G26", not other scripts' numerals), where their `\d` and `isdigit` accepted any
  Unicode digit.
- Descriptions are theirs, except `parse_morphology` (it describes the Hebrew codes the
  packs use, STEPBible's, e.g. 'HVqp3ms'), `get_cross_references` (TSK only),
  `find_similar_passages` (at most 20, examples the packs give), the default `limit`
  (the user's setting), `lookup_verse` (the user's translation) and the ancient tools
  (no "None is Scripture"; the canon label is described as a label the user can turn
  off). Descriptions are static: they never change with the user's settings.
- English verse text is the user's translation (below), where theirs was the BSB.
- Canon labels, verdicts and source filters follow the user's preferences (below).
- Known gap (also in tier 1): a name or topic over about 50 KB makes SQLite refuse the
  `LIKE` pattern, and the tool crashes (rho reports "Tool crashed") instead of
  returning an error.

## Preferences

A user's study settings live in the host app. Core asks for them on every tool call:
`config :bezalel_core, :preferences, {module, function, args}` is called as
`apply(module, function, args ++ [ctx])` with the `Rho.Tool` ctx (it carries
`:session_id`, so a host serving several users can map the session to a user) and
returns a `Bezalel.Study.Preferences` or a map, which `Preferences.new/1` checks (unknown
keys ignored, an invalid value the default). Unset, every call gets the defaults. Each
tool's `run/2` calls `Preferences.current(ctx)`; `result/2` takes the preferences
explicitly (tests pass them, so they stay async), and `result/1` uses `current/0`.

| Setting | Default | What it does |
|---|---|---|
| `approach` | nil (`Prompt.default_approach/0`) | The editable part of the system prompt |
| `scripture_labels` | true | Canon-status labels on non-biblical sources |
| `excluded_sources` | `["editorial:verdicts", "method:genre_guidance"]` | Sources left out (below) |
| `limit` | 8 (1–50) | Default result count of the list tools, held to each tool's maximum |
| `translation` | `"net"` (`"net"`, `"bsb"`) | The English the tools quote |
| `image_model` | `"openai:gpt-image-2"` (`DrawImage.models/0`) | "Pictures by": the model `draw_image` draws with |
| `pushback_model` | nil (none) | "Pushback from": the model that pushes back on a reply ([Pushback](#pushback-another-model-reviews-a-reply)); any rho model spec |

### Sources

`Bezalel.Study.Sources.all/0` lists them with a label, group and description for a
settings screen; `keys/0`:

- Ancient sources: `ancient:josephus`, `ancient:targum`, `ancient:qumran`,
  `ancient:philo`, `ancient:pseudepigrapha`, `ancient:rabbinic` (one per registry
  corpus). Off: the corpus is left out of a search of `all` (and josephus stops being
  the default corpus); naming it, or citing one of its works, is an error saying the
  user switched it off. `ancient:qumran` covers the scrolls pack's works too;
  `ancient:apostolic_fathers` is the fathers pack's corpus (on by default, as every
  corpus).
- Biblical manuscripts: `manuscripts:dss`, on by default: the Dead Sea Scrolls'
  readings in `compare_biblical_versions`. Off: the DSS rows are left out of a default
  comparison; asking for `versions: ["DSS"]` is the switched-off error.
- Editorial: `editorial:verdicts`, off by default. studybible-mcp's maintainer's
  judgements: the curated "contrast" links on ancient passages, the verdict sentences
  and the `contrast` field of the ⚠ notes, the confessional sentence of a corpus caveat
  (`Registry` `verdict`: "the NT's judgment governs", "his Logos is not the incarnate
  Son", "never a basis for doctrine"), and `compare_biblical_versions`'s Westminster
  Confession line. Shown, they are credited: "Verdict (studybible-mcp): …". Factual
  provenance warnings (interpolations, emendations, editions, dates, translation
  caveats) are not a source and always stay.

  The ⚠ notes (`Bezalel.Study.Ancient.Notes`): all 46 distinct notes in the pinned
  ancient pack (83 rows) were read and sorted sentence by sentence. Those found to be
  provenance only are listed and shown as they stand; the 26 that mix in a verdict or a
  canon statement are kept in core, keyed by the CRC-32 of the note text, as their
  provenance part (always shown), their canon statement (with scripture labels, reworded
  by tradition: CD 16:2–4's "Jubilees … is not Scripture" becomes "Jubilees is Scripture
  in the Ethiopian and Eritrean Orthodox Tewahedo canons and for Beta Israel; it is not
  in other canons") and their verdict (with the verdicts: e.g. 4 Ezra 7:28–29's "Christ,
  raised, dies no more", 1 Enoch 15:8–12's "compatible with, not taught by,
  Scripture"). A note the table doesn't know (a rebuilt pack) is shown as it stands,
  except that one of kind `contrast` then needs the verdicts.
- Theologians: `theology:heiser`, `theology:bradley`, `theology:owen`,
  `theology:stott`, `theology:lennox`, `theology:synthesis` (the `source_author` values
  in the notes pack). Off: their entries and themes are left out; naming the author is
  an error.
- Notes and reference: `notes:study_notes` (Tyndale), `notes:translation_notes_uw`,
  `notes:translation_notes_sil`, `notes:dictionary` (Tyndale), `notes:key_terms` (FIA),
  `crossrefs:themes` (studybible-mcp's doctrinal theme chains; the TSK cross references
  stay).
- Background: `ane:context` (studybible-mcp's ANE summaries).
- Methods: `method:torah_weave` (Kline; also drops `lookup_verse`'s Torah weave hint),
  `method:genre_guidance` (Fee & Stuart's guidance appended by `lookup_verse`; off by
  default, an evangelical method; when on it is credited: "Genre guidance after Fee &
  Stuart, *How to Read the Bible for All Its Worth* (evangelical):").

A tool whose every source is off is withheld (`Sources.withheld_tools/1`,
`Tools.withheld/1`): the ancient tools, `get_theology_context`, `get_study_notes`,
`get_bible_dictionary`, `get_key_terms`, `get_ane_context`, `get_torah_weave`. A tool
with content of its own (`lookup_verse`, `get_cross_references`,
`compare_biblical_versions`) only loses that part. A withheld tool called anyway
answers with the switched-off error; so do the multi-source tools (the ancient tools,
`get_theology_context`, `get_study_notes`) when every one of their sources is off
(`Sources.check_tool/2`), naming them, instead of an empty answer.

### Scripture labels

The registry's tags carry a canon status, now by tradition where traditions differ:
"Not Scripture" for Josephus, the Targum, Qumran, Philo and the Mishnah; 1 Enoch
"Scripture in the Ethiopian and Eritrean Orthodox Tewahedo canons and for Beta Israel;
not in other canons"; 4 Ezra "Scripture in the Ethiopian Orthodox Tewahedo canon (as
Ezra Sutuel); printed in Slavonic Orthodox Bibles (as 3 Esdras) and the Vulgate's
appendix (as 4 Esdras); not in the Jewish, Catholic or Protestant canons". The
corpus caveat leads with the corpus's status ("- Josephus: Not Scripture. A Jewish
historian…"). `compare_biblical_versions` replaces their Apocrypha line with a canon
line by tradition ("Tobit is in the Catholic and Orthodox canons, not the Jewish or
Protestant ones"; 1 Esdras, 3 Maccabees, Psalm 151 and the Prayer of Manasseh: the
Eastern Orthodox canon; 4 Maccabees: an appendix to Greek Orthodox Bibles; the Psalms of
Solomon: no church's canon), and marks such rows "(not in the Hebrew Bible)" where theirs
said "(Apocrypha)". With `scripture_labels` false, the statuses and the canon line are
left out and the provenance stays.

### Translation

`lookup_verse`, `word_study`'s examples, `search_by_strongs`, `find_similar_passages`
and `graph_enriched_search` quote the user's translation: the NET (default) from the
translations pack (`translation_verses`, keyed by the core pack's references), or the
BSB from the core pack (`bsb_verses`). The words, Strong's numbers and glosses stay
STEPBible's. The heading labels it, "(BSB)" or, as the NET's terms ask for software on
the internet, "([NET](http://netbible.org))"; each result's data carries `translation:
%{key, abbreviation, url}` and `translation_note`. A verse the translation lacks shows
STEPBible's gloss marked [gloss]. If the NET is chosen and the translations pack isn't
readable, the tools quote the BSB and say so in one line ("The NET Bible isn't on this
device…"). The NET's permission (netbible.com/copyright) is for non-commercial use, with
"(NET)" after each quotation and the acknowledgement in `Translations.get("net").copyright`
shown by the app; the NET's notes are not licensed and are not in the pack.

Changed result data: a verse view's `bsb` (was it the BSB) is now `translated` (is it
the chosen translation's text), and `lookup_verse`'s result adds `translation`,
`translation_note` and `genre_guidance`.

## Sources

Why and what Kevin decided: [decisions/2026-10-18-sources.md](../decisions/2026-10-18-sources.md).

Every tool's `run/2` returns `{:ok, {:details, markdown, data}}`, `data` with
`citations`: a `Bezalel.Study.Citation` for each record the Markdown shows, in display
order, without repeats. Under each record the Markdown has one `Source:` line built from
the same citations (`Citation.source_line/1`), so the model can copy the link into its
answer (the prompt's rule 6). A citation is the record's `work` (`"net"`, `"bdb"`,
`"josephus"`, `"dss"`, `"theology:stott"`…; `Citations.work_title/1` names it), a
`label`, its reader `url` (nil for a print-only book), `locator`, `book` (author, title,
year, for a book), `licence` (CC BY-NC sources, which ask for credit with each use),
`dataset_url` (the pinned file imported), `translation` and `original`.

`translation` is `:published`, `:assistant`, `:unpublished_draft` or `:machine`. `:assistant` marks
a text the tool gives only in its original language (every Dead Sea Scroll, Philo's
sections without Yonge, Septuagint rows without Brenton, Targum Onkelos, whose English is
Metsudah's of the Hebrew Torah): any English the model gives is its own, an AI
translation, and its Source line says so; `original` links the original. The 26 "Heiser
Literal Translation" rows of the textual-variants data are `:unpublished_draft`: printed
as "Unpublished draft rendering (AI-assisted), not Heiser's", never as Heiser's, with
the verse's Hebrew and Greek on STEP and any Dead Sea Scroll witness as `original`.
`:machine` marks a published machine translation the tool quotes, the Apostolic
Fathers' CAFE English (GPT-4o drafts): its Source line says "machine translation:
AI-generated English, not a published human translation; say so when you quote it",
with Lake's Greek as `original`. A host app should mark it as it marks the other two
(the phone app's sources view and the website's citation list key on the value).

`Bezalel.Study.Citations` holds every URL template (checked against the live sites on
2026-10-18; `test/bezalel/study/citations_test.exs` pins each to a verified example):

| Work | Link |
|---|---|
| NET | `https://netbible.org/bible/{Book+Name}+{c}:{v}` (a superscription: verse 1) |
| BSB | Bible Hub `https://biblehub.com/{slug}/{c}-{v}.htm` |
| Hebrew, Greek, Septuagint, Tyndale notes | STEP `https://www.stepbible.org/?q=version={THOT, THGNT, LXX, TNotes}@reference={ref}` |
| Brenton | `https://ebible.org/eng-Brenton/{BOOK}{cc}.htm#V{v}` (Psalms three digits, Daniel `DAG`, Rahlfs's 2 Esdras as Ezra and Nehemiah) |
| BDB, Strong's | `https://biblehub.com/bdb/{n}.htm`, `https://biblehub.com/{hebrew,greek}/{n}.htm` |
| LSJ | `https://lsj.gr/wiki/{lemma}` |
| Abbott-Smith | the Internet Archive scan at the entry's page, `priv/study/abbott_smith_pages.json` (built by data/'s `mix bezalel.data.abbott_smith` from the TEI's page breaks), with the book reference |
| STEP brief lexicons, morphology, proper names | `https://www.stepbible.org/?q=strong={Hnnnn}`; the STEPBible-Data repository (no page per code or name) |
| TSK | `https://www.openbible.info/labs/cross-references/search?q={Book}+{c}%3A{v}` |
| unfoldingWord, SIL notes | Door43 `tn_{BOOK}.tsv`; opentn.bible (no page per note) |
| Tyndale dictionary, FIA key terms | Aquifer's Markdown at the pinned commit, `{file}.content.md#{heading-anchor}` (one file per initial, past a leading "The") |
| ACAI | `https://github.com/BibleAquifer/ACAI/blob/{commit}/{type dir}/md/{Name}.md` |
| Theographic | `https://theographic.netlify.app/{person,place}/{id}/`, `/event/{slug(title)}_{id}/` |
| Torah Weave | `https://chaver.com/torah-weave/{Book}/{book}-unit-{n}/{book}-unit-{n}` |
| Josephus | Perseus Hopper, Whiston (or Niese when there's no English) by book and section |
| Philo | Scaife, Yonge (`1st1K-eng1`) or the Greek (`1st1K-grc1`) by section |
| Onkelos, Mishnah | Sefaria `Onkelos_{Book}.{c}.{v}`, `Mishnah_{Tractate}.{c}.{m}` |
| 1 Enoch, 4 Ezra | the stored Wikisource revision; eBible's KJV 2 Esdras |
| Dead Sea Scrolls | Leon Levy `…/manuscript/{siglum}-1` (biblical manuscripts only where the scrolls pack names them); the Israel Museum for 1QIsaa, 1QS, 1QpHab, 1QM, 11Q19; Cambridge's CD MS A (cols. 1–16) and MS B (19–20); 1QHa as DJD 40 |
| Apostolic Fathers | the passage's line of CAFE's English at the pinned commit, `github.com/jcuenod/CAFE/blob/{commit}/{file}.en.txt#L{n}` (a `:machine` citation), with Lake's Greek line in jtauber/apostolic-fathers as its original (CAFE numbers its lines as the Greek file it translated) |
| Theology summaries | Heiser's and Owen's stored URLs and pages; Stott, Lennox, Bradley as their book (author, title, year; no edition, which the data doesn't record) "on" the chapter |
| ANE entries, Fee & Stuart | book references as given |
| Textual variants | their stored citation and URL (none in the data version 1 pack) |

The session keeps a tool's card and citations (`Bezalel.Agent.Details.keep_details/2`, rho's
`:keep_details`); `Bezalel.Agent.Reply` collects a reply's citations as it streams and
`Reply.sources/1` marks each `cited` when the answer links its URL (the whole URL, so a
link to John 3:16 doesn't cite John 3:1) or names its book's title; a stored reply's
`Bezalel.Library.Message` has the same as `citations`. A session from before citations
kept the bare card: it reads as a card with no citations. The apps list a reply's
sources grouped by work (`Citations.by_work/1`), the cited ones first, with an "AI
translation" mark and the `original` link where `translation` isn't `:published`; the
credits page (`Bezalel.Study.Credits`) stays the licence page.

## The system prompt

`Prompt.system_prompt(prefs, surface: text, ask_model: true)` is up to four parts:

1. `Prompt.fixed(prefs)`, the part no user edits and kept minimal: Bezalel is a
   companion for studying the Bible; use the tools, quote what they return and cite it,
   say where each claim comes from, don't invent, label every quotation with its
   translation (the NET linked to the verse's page on netbible.org, unaltered), and link
   each source it uses with the Source link the tool gave, never one of its own, saying
   when English is its own translation and linking the original ([Sources](#sources)).
   Then a neutral guide to the
   tools the user's preferences leave on (withheld tools are not named), and a line
   naming the sources the user switched off, so the model doesn't supply them from
   memory.
2. The approach: `prefs.approach`, else `Prompt.default_approach/0`. Everything else
   lives here (persona, audience, hermeneutics, treatment of traditions, answer style),
   so the user can move it. The default is neutral: a companion for pastors, teachers and
   curious readers; the text in its own languages, the world it came from (ancient Near
   Eastern and Greco-Roman context, neighbouring texts) and how Jewish, Christian
   (Catholic, Orthodox, Protestant) and historical-critical readers have understood it,
   each reading credited to who holds it; the evidence and range of readings laid out
   without settling disputed questions unless asked; depth on the first pass; marked
   uncertainty; and method warnings (proof-texting, ignoring genre and context,
   parallelomania, building on low-confidence claims) stated neutrally. No sermon-prep
   frame and no default doctrinal frame; Christian typological readings are one credited
   lens among others.
3. With `ask_model: true` (the host offers rho's `ask_model` tool), `Prompt.other_models/0`:
   ask another model only when the user asks for one ("have Gemini push back", "ask GPT
   what it thinks"), once, with the model they named, purpose `"critique"` for pushback
   or `"second_opinion"` for another view, then answer each of its points (revise where
   it's right, stand your ground with reasons where it isn't), crediting it; one round.
   Without the tool the prompt doesn't mention it.
4. `opts[:surface]`, the host's section on how its screen renders an answer (the phone
   app passes its narrow-column formatting). Core has no platform formatting.

From their `prompts/system_prompt.md` and `hermeneutics.py`: the tool guidance, the
warnings against proof-texting, ignoring genre and context, parallelomania and building
on low-confidence claims, the original-language format and "go deep on the first pass".
Left out of the default: their sermon-prep and "connect to Christ" framing, the "Reading
Scripture in its ancient context" section (one school's framework, largely Heiser's),
the genre table (the genre guidance stays in `lookup_verse`) and the evangelical
interpretation-error list; a user who wants any of it can write it into their approach.

## Materials, drawings and read-aloud

Why and what Kevin decided: [decisions/2026-10-18-materials.md](../decisions/2026-10-18-materials.md).

**Materials** (`Bezalel.Materials`) are the files sent to the agent and received
from it, and what Bezalel makes from them. A material's id is the SHA-256 of its bytes
(`id/1`); `new/2` reads its kind (image, audio, video, document) and media type from its
name, phone formats included (HEIC, M4A, MOV); `derive/4` makes a transcript, an audio
track, a still or a drawing that names what it came from (`derived_from`). Hosts keep
them through `config :bezalel_core, :materials, MyApp.MaterialStore` (a
`Bezalel.Materials.Store`: `put/3`, `fetch/2`, `read/2`, `derivatives/2`, optional
`for_model/2`, each with a ctx carrying `:session_id`), and may lay the files out with
`write_file/3` (`ab/<id>.<ext>` under a directory). Every callback answers only for the
ctx's owner, and `put/3` of an id already kept keeps `merge/2` (the parents of both: two
silent videos share one empty transcript). `to_map/1` and `from_map/1` are the
JSON form for a host's table.

`route/3` says how each goes to a model, by `Rho.Models.inputs/1`: pictures attach (by
reference; rho fetches the bytes through `config :rho, :resolve_attachment,
{Bezalel.Materials, :resolve, []}` when it builds a request; one the providers don't take,
such as HEIC, only through a store with `for_model/2`, else by name), a PDF attaches to a model
that takes PDFs and otherwise goes as its extracted text, audio and video go as their
newest transcript (directly or through the audio track: rho sends no sound, and no model
Bezalel runs watches a video), a text file as its text, other documents by name.
`attachments/4` turns that into rho's attachments for `Rho.Session.user/2`, or returns
`{:missing, materials}` for audio and video still to transcribe. `video_notice/0` is the
text both apps show before a video is sent.

**`draw_image`** is not a study tool (it reads no pack and has no source to switch off),
so it is in `Tools.materials/0`, which a host offers beside `all/0` once it has a store.
It takes `prompt`, `references` (one material id: req_llm's edits form carries one
image) and `size` (`square`, `landscape`, `portrait`). It draws with the user's
"Pictures by" (`prefs.image_model`, one of `DrawImage.models/0`: `openai:gpt-image-2`,
the default, at 1024×1024, 1536×1024 or 1024×1536 as JPEG, a reference going to the
edits endpoint; `google:gemini-3.1-flash-image` or `google:gemini-3-pro-image` at 1:1,
3:2 or 2:3, picture only, a reference sent with the words). It checks for a store, the
reference and the chosen provider's API key (`Rho.Auth.credential(:openai | :google)`)
before it spends anything; a missing key is named, with where to add it ("Settings
(Gemini, API key)") or to choose another model under Pictures by. Then it calls
`ReqLLM.generate_image/3`, keeps the drawing (received, `:generated`, `derived_from`
its reference, `meta.model` the model) and answers rho with it by reference, so the
chat draws it from the store and the model reads its ref. `run/3` takes the
preferences explicitly; tests replace the image call and the credential through
`config :bezalel_core, :draw_image`.

`Bezalel.Library.Message` and `Bezalel.Agent.Reply` list a message's materials by
reference (`materials`, `%{id, kind, mime, name, about, entry}`) beside the pictures
stored inline (`images`), which older sessions and model-made pictures still have.

**Read-aloud.** `Bezalel.Speech.speakable/1` turns a reply's SUMMARY into text for a
voice: Markdown read as a listener hears it (headings, list items and table rows as
sentences, a row with its column names; no code blocks, URLs, images or footnote marks),
Hebrew and Greek replaced by the transliteration the model put in parentheses after
them or dropped, Strong's numbers in parentheses dropped, and references said aloud ("1
Cor 13:4-7" is "First Corinthians 13 verses 4 to 7").

## Pushback: another model reviews a reply

Kevin's ask: "Claude generates the answer and Gemini provides pushback", like a code
review. `Bezalel.Agent.Pushback` runs it on rho's consult (`Rho.Consult`, `rho ~> 0.3`);
the decision record is `decisions/2026-10-18-pushback.md`.

- **The critic** is the user's "Pushback from" (`prefs.pushback_model`, none by
  default). Its brief, `Pushback.critic_prompt/0`, is a study code review: claims
  against the tool results they cite, citations that don't support their claim,
  textual and linguistic accuracy, missing or one-sided perspectives, overreach beyond
  the evidence; a numbered list, most serious first, each point with its severity
  (major, minor, nit) and evidence; no rewrite, no confessional side.
- **What it reads** (`Pushback.brief/1`): the question as the lead got it (each
  attachment's envelope included; its pictures and PDFs by reference,
  `Pushback.attachments/1`), every tool call of the reply with its result (4,000
  characters each, 24,000 in all, Source lines included) and the answer.
- **One round per reply.** `Pushback.target/1` takes the conversation's last reply if
  it finished with an answer (pi's `stopReason` `stop` or `length`, not one Bezalel
  wrote); the lead's answer to a critique, a reply already critiqued, and a reply whose
  lead had it critiqued within its turn (`ask_model`, purpose `critique`) are refused.
  The critique is stored as the critic's own message (rho's attributed `model_message`
  entry), the lead is prompted with it and `Pushback.instruction/0` ("Respond to each
  point: revise where it's right, stand your ground with reasons where it isn't…"),
  and its answer is the reply after it. A critique that comes back after the user
  moved on (asked something else meanwhile) is not added: it would answer a reply
  that is no longer the last, and the round isn't used up.
- **Three ways in.** A per-conversation switch (the app's) calls `Pushback.auto/4` with
  the finished reply after each `agent_end`; the Pushback button on the last reply
  (`Pushback.offered?/2`, which agrees with `target/1` through the message's
  `stop_reason` and blocks) calls `Pushback.start/3`; asking in words is the prompt's
  rule and rho's `ask_model` tool, within the lead's turn. `start/3` answers at once
  with a sentence for the user when it can't run: no critic chosen, the critic's
  provider not signed in (`Rho.Consult.allowed/1`: "Gemini (Google) isn't signed in"),
  a reply still running, nothing to push back on, or the round already had.
- **On screen.** The critique streams on the loop's events (`consult_start`,
  `consult_delta`, `consult_end`). The app folds them into a reply started with
  `Bezalel.Agent.Reply.pushback/4` (any other reply ignores a consult outside a turn,
  so a critique never lands in the user's next reply): `consult`, and a CONSULT block
  ahead of the lead's answer. A stopped consult ends it `:stopped`; a failed one ends it
  `:done` with `reason: :consult_failed` and the error (no run failed, so the app's
  failed-run path, which drops entries and asks again, must not run). Stored, the
  critique is a `Bezalel.Library.Message` with `role: :consult`, `model`, `purpose` and
  `text` (and the same CONSULT block in `blocks`); an `ask_model` call inside a reply is
  a CONSULT block in place of its TOOL CALL, streaming by the consult's id. A CONSULT
  block has `"model"` and `"purpose"`; `Pushback.title/2` names it ("Pushback · Gemini
  3 Pro"). The consult's cost is recorded in the session (rho's `consult` entry, in
  `Rho.Session.totals/1`), and stopping the loop stops it.
- **The same brief in words.** The app sets `config :rho, :consult_system,
  {Bezalel.Agent.Pushback, :system, []}`, so the critic the lead asks for itself gets
  the study brief too (rho's own for other purposes).

## Tests and fixtures

The phone app's `data/scripts/make_fixtures.py` cuts a small copy of each pack from its
`data/out` into this repository's `test/fixtures/packs` (it writes to
`../bezalel_core/test/fixtures/packs` by default: Genesis 1–2, Exodus 31, Psalm 22,
John 3, Jude, plus the verses, people, places, articles, ANE entries, theology content
and ancient passages the tests name; about 6 MB in all; its docstring lists what each
table keeps; `--pack <name>` cuts one). Tests in `test/bezalel/study/` run against
those, never the real packs; they port studybible-mcp's handler tests (and its
theology, research-sources, broad-entry, textual-variant, biblical-versions and
ancient-corpus tests) and add the Exodus 31 cases. `translations.sqlite` holds the NET
of exactly the verses the core fixture's `bsb_verses` has. `translations.sqlite` and
`scrolls.sqlite` are cut by this repository's `data/` (`mix bezalel.data.fixtures`):
the scrolls fixture keeps 11Q13, 4Q174 and 4Q246 whole, 1QM column 1 and fragment 3,
4Q405 frg. 23 i, and the biblical readings of Deut 32:8, Isa 53:11, Ps 22:16, Deut
1:10, Josh 5:0 and Mal 4:1 (`scrolls_test.exs`). `fathers.sqlite`, cut the same way,
keeps Didache 0–1, 9 and 14, Ignatius To the Ephesians 20, 1 Clement 5, Barnabas 18,
Hermas Vision 1.1, Mandate 4.1 and Similitude 9.30, Polycarp To the Philippians 10 and
the Moscow epilogue (`fathers_test.exs`). The ported cases that assert
studybible-mcp's wording pass `Preferences` with the BSB and a limit of four (their
defaults); `preferences_test.exs`, `source_filters_test.exs` and `translations_test.exs`
cover the settings, the source filters and verdicts, the labels, the translations and
the prompt. The phone app's tests read the same fixtures from this dependency. In the
phone app, `mix run --no-start scripts/study_tools_smoke.exs` runs every tool in
`Tools.all/0` against the real packs and fails if one errors or is left out.
