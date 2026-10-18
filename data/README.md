# bezalel_core/data — study data built in Elixir

A separate Mix project (`:bezalel_data`) inside bezalel_core that builds
study data the tools read, starting with the **`translations` pack**: English
verse texts other than the BSB (which stays in the core pack's
`bsb_verses`). Today that is the NET Bible.

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
mix bezalel.data.fixtures   # → ../test/fixtures/packs/translations.sqlite
```

Needs the network for the first run (66 requests, about 30 seconds); later
runs reuse the verified responses in `work/net/`. Writes only `work/` and
`out/` (both gitignored), and the fixture with `bezalel.data.fixtures`.

`mix bezalel.data.net --core PATH` compares NET's verse set with the BSB
references (`bsb_verses.reference`) of a core pack; without `--core` it uses
the phone app's `../../bezalel/data/out/core.sqlite` when that is there.

`mix bezalel.data.fixtures` cuts the fixture core's tests read: the
`translations` rows and the verses for exactly the references in
`test/fixtures/packs/core.sqlite`'s `bsb_verses`, with the same `pack_meta`
plus a `fixture` row. Run it after `bezalel.data.net`.

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

## Publish

The apps read one URL, **https://bezalel.genericjam.com/packs/manifest.json**
(schema 1, parsed by the phone app's `Bezalel.Packs.Manifest`), served from
the Cloudflare R2 bucket `bezalel-packs`. `mix bezalel.data.publish` publishes
the packs built here as the next data version **without uploading the base
again**: the five base entries keep their v1 URLs and checksums exactly as
`base.json` pins them, so an app that has them sees the same `raw_sha256`,
records the new version and downloads nothing.

```sh
cd data
mix bezalel.data.net                    # if out/translations.sqlite isn't built
mix bezalel.data.publish --dry-run      # what would be uploaded; writes out/manifest.json
mix bezalel.data.publish
```

Who can run it: someone with `npx` whose wrangler is logged in
(`npx wrangler@4 login`) to the Cloudflare account that owns the bucket, and
`zstd` on the path. A real publish also needs `data/` committed: the manifest
names the bezalel_core commit that built the new packs.

What it does, in order:

1. Reads the published manifest (data version N − 1) and stops unless it
   lists the five base packs with exactly `base.json`'s URLs, sizes and
   sha256s; checks each base file is still served with its size. The base
   entries' descriptions, licences, `required` and tables are copied from
   the published manifest.
2. Checks `out/translations.sqlite` was built from `pins.json`'s NET
   responses, compresses it with `zstd -19` (as the phone app's
   `make_packs.py` compresses the base) and uploads it to
   `packs/v<N>/translations.sqlite.zst` with
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
(`repo`, `commit`). Its `translations` entry is `required: false`. Apps
that don't know a pack ignore its entry.

## Layout

| Path | What |
|---|---|
| `pins.json` | Every download, by URL and sha256 |
| `base.json` | The frozen base packs (data version 1) |
| `lib/bezalel/data/net.ex` | NET API markup → rows |
| `lib/bezalel/data/pack.ex` | Writes and reads pack files |
| `lib/bezalel/data/report.ex` | The import report and the verse-set comparison |
| `lib/bezalel/data/books.ex` | The 66 books: STEP code, name, chapters |
| `lib/bezalel/data/download.ex` | Cached, checked downloads |
| `lib/bezalel/data/publish.ex` | Assembles the manifest (pure) |
| `lib/mix/tasks/` | `bezalel.data.net`, `bezalel.data.fixtures`, `bezalel.data.publish` |

## Checks

```sh
mix format
mix credo --strict
mix compile --warnings-as-errors
mix test
```

The tests use small inline inputs and no network.
