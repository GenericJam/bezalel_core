# bezalel_core/data — study data built in Elixir

A separate Mix project (`:bezalel_data`) inside bezalel_core that builds
study data the tools read: the **`translations` pack**, English verse texts
other than the BSB (which stays in the core pack's `bsb_verses`): the NET
Bible, the JPS 1917 and the Literal and Simplified Texts adapted from
unfoldingWord's ULT and UST; and the **`scrolls` pack**, the Dead Sea Scrolls' major
non-biblical works and the biblical manuscripts' readings, from ETCBC/dss.

Bezalel's study tools are an Elixir port of
[studybible-mcp](https://github.com/djayatillake/studybible-mcp) by
[@djayatillake](https://github.com/djayatillake) and the Study Bible MCP
contributors (MIT); the other packs are built by its pipeline (see the phone
app's [data/README.md](https://github.com/GenericJam/bezalel_mob/blob/master/data/README.md)),
and this pack follows their conventions.

## The base

The five packs studybible-mcp's pipeline builds (`core`, `notes`, `lxx`,
`ancient`, `graph`) are frozen as published data version 1:
[base.json](base.json) pins each by URL and sha256, with the studybible-mcp
and bezalel_mob commits that built them. New data is built here, in Elixir,
as packs of its own or as additions to those; the Python pipeline (the phone
app's `data/build.sh`) isn't run again, except to replace one of its
importers at a time.

On 2026-10-17 the pipeline was rerun once on Linux at the same pins as a
check: all five packs came out with the same rows (compared by SQL dump),
differing only in the recorded SQLite version, SQLite's planner statistics,
and about 400 near-tie similar-passage scores in `core` (floating point on
another CPU). `base.json` records the details.

## Build

```sh
cd data
mix deps.get
mix bezalel.data.translations  # → out/translations.sqlite, out/{net,translations}_report.txt
mix bezalel.data.scrolls    # → out/scrolls.sqlite, out/scrolls_report.txt
mix bezalel.data.fixtures   # → ../test/fixtures/packs/{translations,scrolls}.sqlite
mix bezalel.data.abbott_smith  # → ../priv/study/abbott_smith_pages.json
```

Needs the network for the first run (NET: 66 requests, about 30 seconds;
JPS: one 1 MB zip; ULT and UST: 122 files, about 170 MB; scrolls: 19
ETCBC/dss files, 48 MB; and the base core pack, 26 MB, for both, unless
`--core PATH` names a copy); later runs reuse the verified downloads in
`work/`. Writes only `work/` and `out/` (both gitignored), and the fixtures
with `bezalel.data.fixtures` (`--pack translations` or `--pack scrolls` for
one).

`mix bezalel.data.translations` compares each translation's verse set with
the BSB references (`bsb_verses.reference`) of the base core pack
(`out/net_report.txt`, and `out/translations_report.txt` per book the
translation has); `--core PATH` names a copy of it (checked against
`base.json`), e.g. `~/code/bezalel_ca/var/packs/core.sqlite`.

`mix bezalel.data.fixtures` cuts the fixture core's tests read: the
`translations` rows and the verses for exactly the references in
`test/fixtures/packs/core.sqlite`'s `bsb_verses`, with the same `pack_meta`
plus a `fixture` row. Run it after `bezalel.data.translations`.

`mix bezalel.data.abbott_smith` writes core's `priv/study/abbott_smith_pages.json`
(committed; not a pack): the printed page each Abbott-Smith entry starts on, by
Strong's number, from the TEI edition's `<pb n>` page breaks at the commit the core
pack's `abbott_smith_def` was built from, and the Internet Archive scan's page numbers
(`pins.json` → `abbott_smith`, both sha256-pinned), for the lexicon citations' links
into the scan (`Bezalel.Study.Citations.abbott_smith/2`). 5,401 entries; the 470 pack
entries the TEI keys without a Strong's number link the scan's first page.

## The `translations` pack

`translations.sqlite`, page size 4096, ANALYZEd and VACUUMed, integrity
checked, like the packs `make_packs.py` writes:

| Table | Columns | Licence |
|---|---|---|
| `translations` | `key` (PK: `net`, `jps1917`, `ult`, `ust`), `name`, `abbreviation`, `url`, `copyright` (the acknowledgement or attribution to show), `licence`, `source_url`, `source_sha256` (digest of the source files) | as the translation |
| `translation_verses` | `translation`, `reference` (STEP form: `Gen.1.1`; a Psalm superscription is verse 0, `Psa.3.0`), `book`, `chapter`, `verse`, `text`; PK `(translation, reference)` | each translation's own: NET Bible free non-commercial use by permission; JPS 1917 public domain; ULT, UST CC BY-SA 4.0 |
| `pack_meta` | `key`, `value`: `pack`, `description`, `tables`, `sqlite_version`, `licences`, `built_by`, `net_source`, `net_sha256`, `jps_source`, `jps_sha256`, `ult_source`, `ult_sha256`, `ust_source`, `ust_sha256` (each the digest of the pinned files), `versification`, `core_sha256` | — |

### NET Bible

*Scripture quoted by permission. Quotations designated (NET) are from the
NET Bible® copyright ©1996, 2019 by Biblical Studies Press, L.L.C.
http://netbible.com All rights reserved.* (`translations.copyright`)

Terms ([netbible.com/copyright](https://netbible.com/copyright/)):
non-commercial apps may quote it; each quotation is followed by "(NET)", and
in internet-connected software "NET" links to http://netbible.org. The
translators' and study notes are **not** licensed for this, and none are
imported. The text is not altered.

**Source.** Everything in the pack (words, small capitals, Psalm
superscriptions, which paragraphs are headings) comes from the publisher's
own web service, the NET Bible API at
[labs.bible.org](https://labs.bible.org/api_web_service) (Biblical Studies
Press: "If you want to use the NET Bible text in your web application or
service, this is the easiest way"): one request per book,
`?passage=<Book> 1-<last chapter>&type=json&formatting=full`. The service
is not versioned, so each book's response is pinned by sha256 in
[pins.json](pins.json); when the publisher revises the text the build stops
and names the books.

**Why not eBible.org or the Free Use Bible API.** Both offer the NET as files
(eBible's `engnet_usfm.zip`, and `bible.helloao.org/api/eng_net`, which is
generated from eBible's). Checked on 2026-10-17, that text is an older NET
edition (eBible's own notice reads ©1996-2016): about 3,700 verses differ in
wording from the current one (Jeremiah 19:15 "the LORD who rules over all"
for "the LORD of Heaven's Armies", Exodus 25:10 in feet rather than inches).
It is also damaged in conversion: phrases doubled in the New Testament's Old
Testament quotations (Matthew 19:4 "made them male and female them male and
female"; 2 Corinthians 10:17, 1 Corinthians 15:27, James 2:8, John 12:38),
words run together ("writethe", Revelation 2:18), about 40 stray asterisks,
and translators' notes left in Isaiah 43. The API has none of these.

**What the import does** (`Bezalel.Data.Net`), from the API's markup:

- keeps the words and punctuation as given; text in small capitals
  (`<span class="smcaps">`) is written in capitals, as print reads, so the
  divine name YHWH is "LORD" (5,868 rows) and *Adonai*/*kyrios* stays
  "Lord";
- moves each Psalm superscription (`<p class="psasuper">`, sent at the start
  of verse 1) to verse 0, the packs' convention: 116 superscriptions, the
  same 116 Psalms as the BSB's;
- drops headings: the Song of Songs speaker labels (`sosspeaker`, 57, e.g.
  "The Beloved to Her Lover:"), the Hebrew letters heading the stanzas of
  the acrostics in Psalm 119 and Lamentations 1–4 (`lamhebrew`, 110,
  "א (Alef)") and three section titles (`paragraphtitle`);
- drops note markers (`<n id="1" />`) and Strong's tags (`<st>`), keeping
  their words;
- turns paragraph and line breaks into spaces and collapses whitespace (the
  API's plain format loses these breaks and runs words together, e.g.
  "Adam.When", which is why the import reads `formatting=full`);
- refuses any element or paragraph class it doesn't know.

**Coverage** (build of 2026-10-17; `out/net_report.txt` has the details):
31,201 rows (31,085 verses and 116 superscriptions). Of the 31,102 verses
of the traditional English numbering, the service leaves out the 15 that
modern critical texts omit (Matthew 17:21, 18:11, 23:14; Mark 7:16, 9:44,
9:46, 11:26, 15:28; Luke 17:36, 23:17; John 5:4; Acts 8:37, 15:34, 28:29;
Romans 16:24), sends Acts 24:7 empty, and has no 2 Corinthians 13:14. The
BSB omits the same 15 and Acts 24:7. So against the real core pack's 31,202
`bsb_verses` references, NET has every one except **2 Corinthians 13:14**:
the NET numbers the end of 2 Corinthians 13 differently (its 13:12 is the
BSB's 13:12–13, and its 13:13, "The grace of the Lord Jesus Christ…", is
the BSB's 13:14).

### JPS 1917

*The Holy Scriptures according to the Masoretic Text: A New Translation*
(Jewish Publication Society of America, 1917): public domain, the Old
Testament only. Key `jps1917`, labelled "(JPS)".

**Source.** eBible.org's USFM, `engjps_usfm.zip` (its `copr.htm`: "Public
Domain"; the build checks), pinned by sha256 in [pins.json](pins.json) →
`jps`: the URL isn't versioned, so a new upload stops the build.

**What the import does** (`Bezalel.Data.Usfm`, `Bezalel.Data.Jps`):

- eBible numbers the verses in the English way and writes the Hebrew
  numbers inline where they differ (`\v 1 (3-1) A Psalm of David… (3-2)
  LORD, how many…`). The numbers are removed (2,056); a Psalm title, the
  Hebrew verses that the base core pack's `verses.reference` numbers as
  English verse 0 (`Psa.3.0(3.1)`), becomes verse 0 (62 Psalms); every other
  verse keeps eBible's English number, also where the core places the Hebrew
  number in another verse (the Decalogue's Hebrew accentuation, Exodus
  20:14–26 and Deuteronomy 5:18–33, and Psalm 13:6: listed in the report);
- the USFM has only `\c`, `\v`, `\p` and the header lines; any other
  marker stops the build;
- kept as eBible gives it (no markup to drop it by, rule 3): a book's first
  words in capitals ("IN THE beginning") and the Psalter's book headings at
  the start of Psalms 1, 42, 73, 90 and 107 ("BOOK I HAPPY IS the man…",
  "BOOK II For the Leader…").

**Coverage** (build of 2026-10-22; `out/translations_report.txt`): 23,207
rows in the 39 books, every one a BSB reference. Of the BSB's 23,261 Old
Testament references, 54 Psalm superscriptions have no row of their own:
where the superscription and the first verse are one Hebrew verse, eBible
prints them as verse 1 with no number between them (Psalm 23:1 "A Psalm of
David. The LORD is my shepherd…"), and they stay there. The study tools quote
the BSB, with a note, for the New Testament.

### Literal and Simplified Texts (ULT, UST, adapted)

unfoldingWord's literal (ULT) and simplified (UST) English translations,
CC BY-SA 4.0. Keys `ult`, `ust`, labelled "(ULT)", "(UST)".

**Source.** The Door43 repositories
[unfoldingWord/en_ult](https://git.door43.org/unfoldingWord/en_ult) and
[en_ust](https://git.door43.org/unfoldingWord/en_ust) at tag `v91` (commits
`35d21595`, `85f274a7`): every book file, `LICENSE.md` and `manifest.yaml`,
each pinned by sha256 in [pins.json](pins.json) → `ult`, `ust`. The build
checks LICENSE.md still states the terms below.

**Licence terms followed.** Removing the word alignment makes the pack's
text a derivative work, which LICENSE.md says must drop the unfoldingWord®
trademark, say what changed, credit "The original work by unfoldingWord is
available from unfoldingword.org/ult" (`/ust`) and stay CC BY-SA. So the
names shown are "Literal Text (ULT, adapted)" and "Simplified Text (UST,
adapted)", and `translations.copyright` (core's
`Bezalel.Study.Translations`, which the importer reads) carries the
original's copyright, that attribution, the changes and the licence. The
CC BY-SA text has its own rows (`translation`), apart from the NET's
non-commercial ones.

**What the import does** (`Bezalel.Data.Usfm`, `Bezalel.Data.Door43`):

- keeps the words (`\w word|attributes\w*`) and drops the alignment and
  section milestones (`\zaln-s |…\*`, `\zaln-e\*`, `\ts\*`); keeps the
  ULT's braces for implied words ("{There are} many");
- a Psalm title (`\d`, before or at the start of verse 1) becomes verse 0;
- drops footnotes (`\f … \f*`; ULT 296, UST 19), as the NET import drops its
  notes, the header lines, and headings by their markers: section headings
  and references (`\s1`, `\sr`, `\r`), the Psalter's book headings (`\ms1`),
  the acrostics' letters (`\qa`) and speaker labels (`\sp`);
- a verse bridge (`\v 4-5`, 70 in the UST) is kept whole on its first
  verse; the later verse has no row (the report lists them);
- any other marker, text outside a verse or a title outside a Psalm's first
  verse stops the build.

**Coverage** (v91, build of 2026-10-22): 59 books each; no Numbers, 1–2
Chronicles, Ecclesiastes, Isaiah, Jeremiah or Ezekiel (not yet released).
The study tools quote the BSB, with a note, for a book that isn't there.
ULT 24,014 rows: every BSB reference of its books except Psalm 133:0, 134:0
and 2 Corinthians 13:14, plus 18 the BSB has no text for: the 15 verses modern
critical texts omit (Matthew 17:21 …), Acts 24:7, 3 John 1:15 and Revelation
12:18. UST 23,940 rows: every BSB reference of its books except 2 Corinthians
13:14 and the 77 later verses of its 70 bridges, plus the same 18 and Psalm
115:0.

## The `scrolls` pack

`scrolls.sqlite`, built like the translations pack (page size 4096,
ANALYZEd, VACUUMed, integrity checked). Hebrew and Aramaic only: no English
translation of the scrolls is openly licensed, so none is imported (the
corpus caveat says any English is the assistant's own).

| Table | Columns | Licence |
|---|---|---|
| `ancient_source_passages`, `ancient_source_passages_fts` | the ancient pack's schema, FTS5 columns and tokenizer (`porter unicode61 remove_diacritics 2`), unchanged: corpus `qumran`, one passage per fragment or column label of a manuscript, its lines numbered; `section_number` the label's lookup key (`Bezalel.Study.Ancient.fragment_key/1`), `book_number` its position, `sort_start`/`sort_end` position × 1000 + line | ETCBC/dss: CC BY-NC 4.0 |
| `ancient_source_biblical_links`, `ancient_source_notes` | the ancient pack's, empty | — |
| `dss_biblical_manuscripts` | `siglum` (ETCBC), `name` (conventional, e.g. 4QDeutj, or null), `site`, `books`, `verses`, `reconstructed_only`, `sort_order` | names: the conventional scholarly designations (facts, no licence needed), as the Leon Levy DSS Digital Library lists them ([dss_names.json](dss_names.json)) |
| `dss_biblical_verses` | `reference` (STEP, the packs' English numbering), `book`, `chapter`, `verse`, `source_reference` (ETCBC's Hebrew numbering), `mt_verse` (0: the core pack has no such verse), `siglum`, `occurrence`, `locator` (fragment or column and lines), `text`, `letters`, `preserved_letters` (outside `[ ]`), `language`; PK `(reference, siglum, occurrence)` | ETCBC/dss: CC BY-NC 4.0 |
| `pack_meta` | `pack`, `description`, `tables`, `sqlite_version`, `licences`, `built_by`, `dss_source`, `dss_sha256`, `versification`, `core_sha256`, `build_sha256` (the importer's and core's files that decide the rows; `Bezalel.Data.Scrolls.build_digest/0`) | — |

**Source.** [ETCBC/dss](https://github.com/ETCBC/dss), the Text-Fabric
release 2.0.1 (tag v2.0.1, commit `47ecc173`, the one the ancient pack's
CD, 1QS, 1QSa and 1QpHab were built from) of the transcription by Martin G.
Abegg Jr., James E. Bowley and Edward M. Cook, CC BY-NC 4.0 (every feature
file's header declares it; the build checks). The 19 feature files it reads
are pinned by sha256 in [pins.json](pins.json) → `dss`. The verse numbers are
mapped from ETCBC's Hebrew numbering to the packs' English one with the base
core pack's `verses.reference` (`Psa.3.0(3.1)`), the base pack checked
against `base.json`.

**Which works.** The 30 compositions and 132 manuscripts registered in
core's `Bezalel.Study.Ancient.Scrolls` (why these:
[../decisions/2026-10-18-dead-sea-scrolls-pack.md](../decisions/2026-10-18-dead-sea-scrolls-pack.md)):
the Qumran copies of the Damascus Document and the Community Rule, the Rule
of Blessings, War Scroll, Hodayot, Temple Scroll, MMT, Florilegium,
Testimonia, Melchizedek, 4Q246, 4Q521, Pesher Nahum, Psalms and Isaiah, the
Songs of the Sabbath Sacrifice, Genesis Apocryphon, Aramaic Enoch, Book of
Giants, Aramaic Levi, Instruction, 4Q252, Sefer ha-Milhamah, Catena A, the
Songs of the Sage, the Copper Scroll, Jubilees, Tobit, the Prayer of
Nabonidus and the Targum of Job; every copy as its own work, never a
composite. Not in ETCBC/dss: the Masada Songs of the Sabbath Sacrifice
(Mas1k), 4Q206a, 4Q173, 3Q4, 4Q253–254a. And every biblical manuscript.

**What the import does** (`Bezalel.Data.Scrolls`), rule by rule, the same
way studybible-mcp's `corpora/qumran.py` made the ancient pack's Qumran
works (checked: the four works it builds from the same files come out
byte-identical to the ancient pack's rows and search columns):

- renders each line from ETCBC's signs with the editorial brackets: `[ ]`
  modern reconstruction, `{ }`/`{{ }}` removals, `< >`/`<< >>`/`^ ^`
  corrections, `( )` alternatives, `vacat` for unwritten space, a circlet
  (U+05AF) after a damaged letter, `◦` an unreadable one, `…` a gap; drops
  ETCBC's analytical morpheme break (׳), which isn't written; keeps the
  Copper Scroll's Greek letters; stops on a sign type it doesn't know;
- search text: reconstruction is a word break and never matched, removals
  and `vacat` deleted, marks and case folded with core's
  `Bezalel.Study.Ancient.Passages` (which folds the queries), Hebrew prefix
  variants as the ancient pack has them;
- a passage's language is Aramaic when most of its letters carry ETCBC's
  `lang` a;
- biblical readings: every word with a book, chapter and verse of the Hebrew
  Bible, consecutive words of one verse in one manuscript joined (` / ` a
  line break), a verse read again later in the manuscript a second
  `occurrence`; a non-numeric line label stops the build;
- leaves out, by rule, and counts in `out/scrolls_report.txt`: the
  non-biblical scrolls not registered (599 scroll nodes: the long tail of
  small fragments, works not judged major, and the non-biblical parts of
  4Q88, 11Q5 and 11Q6; CD, 1QS, 1QSa and 1QpHab are in the ancient pack),
  the 5,815 words of biblical scrolls whose ETCBC `book` is a scroll or
  photograph siglum (unidentified fragments), and the signs in no word
  outside every verse on their line (line ends, gaps between verses). A
  sign in no word between two words of one verse (a `vacat`, an unreadable
  letter) stays in that verse's text.

**Coverage** (build of 2026-10-18): 2,492 passages in 132 manuscripts; 265
biblical manuscripts (262 with an identified verse; 235 from the Qumran
caves, the rest from Masada, Murabba'at, Nahal Hever, Nahal Se'elim, Wadi
Sdeir, Nahal Arugot and unknown sites), 11,919 readings of 8,020 verses in
36 books (none of 1 Chronicles, Nehemiah or Esther); 743 readings wholly
reconstructed, and 349 verses with no letter preserved in any manuscript;
one verse ETCBC numbers that the MT lacks (Josh 5:0, 4QJosha's text before
5:2).

## Publish

The apps read one URL, **https://bezalel.genericjam.com/packs/manifest.json**
(schema 1, parsed by the phone app's `Bezalel.Packs.Manifest`), served from
the Cloudflare R2 bucket `bezalel-packs`. `mix bezalel.data.publish` publishes
the packs built here (`translations`, `scrolls`) as the next data version
**without uploading the base again**: the five base entries keep their v1 URLs and checksums exactly as
`base.json` pins them, so an app that has them sees the same `raw_sha256`,
records the new version and downloads nothing.

```sh
cd data
mix bezalel.data.translations           # if out/translations.sqlite isn't built
mix bezalel.data.scrolls                # if out/scrolls.sqlite isn't built
mix bezalel.data.publish --dry-run      # what would be uploaded; writes out/manifest.json
mix bezalel.data.publish
```

Who can run it: someone with `npx` whose wrangler is logged in
(`npx wrangler@4 login`) to the Cloudflare account that owns the bucket, and
`zstd` on the path. A real publish also needs `data/` and `lib/` committed: the manifest
names the bezalel_core commit that built the new packs.

What it does, in order:

1. Reads the published manifest (data version N − 1) and stops unless it
   lists the five base packs with exactly `base.json`'s URLs, sizes and
   sha256s; checks each base file is still served with its size. The base
   entries' descriptions, licences, `required` and tables are copied from
   the published manifest.
2. Checks `out/translations.sqlite` and `out/scrolls.sqlite` were built
   from `pins.json`'s NET responses, JPS zip, ULT and UST files and ETCBC/dss
   files (both packs also with `base.json`'s core pack, the scrolls pack by
   this checkout's code, its `build_sha256`), compresses each
   with `zstd -19` (as the phone app's `make_packs.py` compresses the base)
   and uploads it to `packs/v<N>/<pack>.sqlite.zst` with
   `Cache-Control: public, max-age=31536000, immutable`. An object already
   at that key is accepted only if byte-identical (an interrupted publish
   resumes); anything else stops the publish (rerun with `--version N`).
3. Writes the manifest to `out/manifest.json` and uploads it, last, to
   `packs/manifest.json` with `Cache-Control: no-cache`, so a client never
   sees a manifest naming packs that aren't there yet.
4. Fetches every upload back with a unique query string (so the answer
   comes from R2, not an edge copy) and compares size and sha256.

Uploads use `npx -y wrangler@4 r2 object put bezalel-packs/<key> --file …
--remote`. The manifest keeps the published fields (`schema`,
`data_version`, `built`, `bezalel_commit` — the bezalel_mob commit that built
the base —, `studybible_mcp`, `sources`, `packs`) and adds `bezalel_core`
(`repo`, `commit`). Its `translations` and `scrolls` entries are
`required: false`. Apps
that don't know a pack ignore its entry.

## Layout

| Path | What |
|---|---|
| `pins.json` | Every download, by URL and sha256 |
| `dss_names.json` | Conventional names of the biblical manuscripts, with their source |
| `base.json` | The frozen base packs (data version 1) |
| `lib/bezalel/data/net.ex` | NET API markup → rows |
| `lib/bezalel/data/usfm.ex` | A USFM book → rows (the JPS, ULT and UST) |
| `lib/bezalel/data/jps.ex` | eBible's JPS 1917: the zip's books, the Hebrew verse numbers mapped |
| `lib/bezalel/data/door43.ex` | Door43's ULT and UST: the releases' books, the licence check, the adaptation's rows |
| `lib/bezalel/data/pack.ex` | Writes and reads pack files |
| `lib/bezalel/data/text_fabric.ex` | Reads Text-Fabric feature files |
| `lib/bezalel/data/scrolls.ex` | ETCBC/dss → the scrolls pack's rows |
| `lib/bezalel/data/scrolls_pack.ex` | The scrolls pack's schema and writer |
| `lib/bezalel/data/report.ex` | The import reports and the verse-set comparison |
| `lib/bezalel/data/books.ex` | The 66 books: STEP code, name, chapters |
| `lib/bezalel/data/download.ex` | Cached, checked downloads |
| `lib/bezalel/data/publish.ex` | Assembles the manifest (pure) |
| `lib/mix/tasks/` | `bezalel.data.translations`, `bezalel.data.scrolls`, `bezalel.data.fixtures`, `bezalel.data.publish` |

## Checks

```sh
mix format
mix credo --strict
mix compile --warnings-as-errors
mix test
```

The tests use small inline inputs and no network.
