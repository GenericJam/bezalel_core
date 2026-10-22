# bezalel_core/data — study data built in Elixir

A separate Mix project (`:bezalel_data`) inside bezalel_core that builds
study data the tools read: the **`translations` pack**, English verse texts
other than the BSB (which stays in the core pack's `bsb_verses`), today the
NET Bible; and the **`scrolls` pack**, the Dead Sea Scrolls' major
non-biblical works and the biblical manuscripts' readings, from ETCBC/dss.
The **`syntax` pack** is each verse's clause structure, from Clear-Bible
MACULA's syntax trees.

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
mix bezalel.data.net        # → out/translations.sqlite, out/net_report.txt
mix bezalel.data.scrolls    # → out/scrolls.sqlite, out/scrolls_report.txt
mix bezalel.data.syntax     # → out/syntax.sqlite, out/syntax_report.txt
mix bezalel.data.fixtures   # → ../test/fixtures/packs/{translations,scrolls,syntax}.sqlite
mix bezalel.data.abbott_smith  # → ../priv/study/abbott_smith_pages.json
```

Needs the network for the first run (NET: 66 requests, about 30 seconds;
scrolls: 19 ETCBC/dss files, 48 MB, and the base core pack, 26 MB, unless
`--core PATH` names a copy; syntax: 956 MACULA files, 533 MB, one request
at a time, and the base core pack likewise); later runs reuse the verified
downloads in `work/`. Writes only `work/` and `out/` (both gitignored), and
the fixtures with `bezalel.data.fixtures` (`--pack translations`, `--pack
scrolls` or `--pack syntax` for one).

`mix bezalel.data.net --core PATH` compares NET's verse set with the BSB
references (`bsb_verses.reference`) of a core pack; without `--core` it uses
the phone app's `../../bezalel/data/out/core.sqlite` when that is there.

`mix bezalel.data.fixtures` cuts the fixture core's tests read: the
`translations` rows and the verses for exactly the references in
`test/fixtures/packs/core.sqlite`'s `bsb_verses`, with the same `pack_meta`
plus a `fixture` row. Run it after `bezalel.data.net`.

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
| `translations` | `key` (PK, `net`), `name`, `abbreviation`, `url`, `copyright` (the acknowledgement to show), `licence`, `source_url`, `source_sha256` (digest of the source responses) | as the translation |
| `translation_verses` | `translation`, `reference` (STEP form: `Gen.1.1`; a Psalm superscription is verse 0, `Psa.3.0`), `book`, `chapter`, `verse`, `text`; PK `(translation, reference)` | NET Bible: free non-commercial use by permission |
| `pack_meta` | `key`, `value`: `pack`, `description`, `tables`, `sqlite_version`, `licences`, `built_by`, `net_source`, `net_sha256` | — |

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

## The `syntax` pack

`syntax.sqlite`, built like the others (page size 4096, ANALYZEd, VACUUMed,
integrity checked) by `mix bezalel.data.syntax [--core PATH]`: how each verse
is put together, for `lookup_verse`'s "Clause structure" section (why this
shape and what was left out:
[../decisions/2026-10-22-syntax-pack.md](../decisions/2026-10-22-syntax-pack.md)).

| Table | Columns | Licence |
|---|---|---|
| `syntax_editions` | `edition` (PK: `WLC`, `SBLGNT`), `language`, `name`, `repo`, `commit_sha` (the pinned commit), `licence`, `attribution` (MACULA's required wording) | — |
| `syntax_verses` | `reference` (PK, STEP form in the packs' English numbering: `Psa.3.0`), `book`, `chapter`, `verse`, `edition`, `source_reference` (the edition's own verse(s), `Psa.3.1`), `source_files` (the tree file(s) in the repo), `clauses` (JSON: the clauses of the sentences touching the verse, `Bezalel.Data.Syntax`); index `(book, chapter, verse)` | MACULA Hebrew / Greek Linguistic Datasets © 2022-2024 Biblica, Inc: CC BY 4.0 (WLC text public domain; SBLGNT CC BY 4.0) |
| `pack_meta` | `pack`, `description`, `tables`, `sqlite_version`, `licences`, `built_by`, `macula_source`, `macula_sha256`, `versification`, `core_sha256`, `build_sha256` (`Bezalel.Data.Syntax.build_digest/0`) | — |

**Source.** [Clear-Bible/macula-hebrew](https://github.com/Clear-Bible/macula-hebrew)
at `47db250b` (`WLC/lowfat/NN-Bbb-CCC-lowfat.xml`, 929 chapter files, 423 MB)
and [Clear-Bible/macula-greek](https://github.com/Clear-Bible/macula-greek) at
`8423afe4` (`SBLGNT/lowfat/NN-book.xml`, 27 book files, 110 MB), each file
pinned by sha256 in [macula_files.json](macula_files.json) (named by
[pins.json](pins.json) → `macula`) and checked once against its git blob at
the commit. Neither is in Git LFS. Cached in `work/macula/`.

**What the import does** (`Bezalel.Data.Syntax`):

- reads, of each word, its text and following punctuation, `ref`, `role`,
  Strong's number (normalised to `H0430`/`G0976`; MACULA's own letter
  suffixes, `0871a`, dropped), English gloss (Hebrew: Cherith's `english`,
  else `gloss`; Greek: the Berean Interlinear's `gloss`, else Cherith's
  `english`) and `lemma`; of each word group its `class`, `rule` and `role`.
  Nothing else: **not the UBS data MACULA marks "Used with permission"**
  (Hebrew `sdbh`, `lexdomain`, `coredomain`, `contextualdomain`; Greek `ln`,
  `domain`), which isn't under its CC BY licence; the report counts every
  attribute seen and names those;
- a sentence becomes its clauses in order; a clause's parts are its words
  grouped by the role they fill (the nearest role between word and clause;
  a role inside a role of the same clause is counted and the outer kept); a
  clause inside a clause is a numbered reference from its part; a clause
  made only of clauses (`ClCl`) is dissolved into them; a group at the top
  of a sentence (MACULA's way of joining clauses with conjunctions) is shown
  as a clause so its conjunctions keep their place;
- for each verse, the clauses with words in it and the clauses around them;
  a word outside the verse keeps only its text, marked with its verse (at
  most 8 words of a run); the sentence's other clauses are counted;
- numbers verses from the base core pack's `verses.reference` (split
  references `Psa.3.0(3.1)` map the WLC's numbering; a Hebrew verse the core
  pack splits between two English verses, `Psa.23.0(23.1)` beside
  `Psa.23.1`, is filed whole under both, and the row says so);
- refuses an element it doesn't know.

**Coverage** (build of 2026-10-22; `out/syntax_report.txt`): 31,201 verses
(WLC 23,213 sentences; SBLGNT 8,010 sentences, 1,194 of them across verses).
Every source verse maps to a core verse. 18 core verses have no row: 14 of
the 15 verses modern critical texts omit (all but Romans 16:24), Acts 24:7,
and Romans 16:25–27 (MACULA Greek's SBLGNT trees end Romans with a 16:24 and
have no doxology). 44.8 MB raw, 4.0 MB with `zstd -19`.

## Publish

The apps read one URL, **https://bezalel.genericjam.com/packs/manifest.json**
(schema 1, parsed by the phone app's `Bezalel.Packs.Manifest`), served from
the Cloudflare R2 bucket `bezalel-packs`. `mix bezalel.data.publish` publishes
the packs built here (`translations`, `scrolls`, `syntax`) as the next data version
**without uploading the base again**: the five base entries keep their v1 URLs and checksums exactly as
`base.json` pins them, so an app that has them sees the same `raw_sha256`,
records the new version and downloads nothing.

```sh
cd data
mix bezalel.data.net                    # if out/translations.sqlite isn't built
mix bezalel.data.scrolls                # if out/scrolls.sqlite isn't built
mix bezalel.data.syntax                 # if out/syntax.sqlite isn't built
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
   from `pins.json`'s NET responses and ETCBC/dss files (the scrolls pack
   also with `base.json`'s core pack and by this checkout's code, its
   `build_sha256`), and `out/syntax.sqlite` from `pins.json`'s MACULA
   files with `base.json`'s core pack and this checkout's code, compresses each
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
(`repo`, `commit`). Its `translations`, `scrolls` and `syntax` entries are
`required: false`. Apps
that don't know a pack ignore its entry.

## Layout

| Path | What |
|---|---|
| `pins.json` | Every download, by URL and sha256 |
| `dss_names.json` | Conventional names of the biblical manuscripts, with their source |
| `base.json` | The frozen base packs (data version 1) |
| `lib/bezalel/data/net.ex` | NET API markup → rows |
| `lib/bezalel/data/pack.ex` | Writes and reads pack files |
| `lib/bezalel/data/text_fabric.ex` | Reads Text-Fabric feature files |
| `lib/bezalel/data/scrolls.ex` | ETCBC/dss → the scrolls pack's rows |
| `lib/bezalel/data/scrolls_pack.ex` | The scrolls pack's schema and writer |
| `lib/bezalel/data/syntax.ex` | MACULA's lowfat syntax trees → the syntax pack's rows |
| `lib/bezalel/data/syntax_pack.ex` | The syntax pack's schema and writer |
| `macula_files.json` | The MACULA files read, by sha256 |
| `lib/bezalel/data/report.ex` | The import reports and the verse-set comparison |
| `lib/bezalel/data/books.ex` | The 66 books: STEP code, name, chapters |
| `lib/bezalel/data/download.ex` | Cached, checked downloads |
| `lib/bezalel/data/publish.ex` | Assembles the manifest (pure) |
| `lib/mix/tasks/` | `bezalel.data.net`, `bezalel.data.scrolls`, `bezalel.data.syntax`, `bezalel.data.fixtures`, `bezalel.data.publish` |

## Checks

```sh
mix format
mix credo --strict
mix compile --warnings-as-errors
mix test
```

The tests use small inline inputs and no network.
