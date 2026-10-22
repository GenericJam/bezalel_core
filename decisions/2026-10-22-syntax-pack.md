# The syntax pack: clause structure in lookup_verse

2026-10-22. Status: accepted (bead `bezalel-bsw.6`, epic `bezalel-bsw`: the
data parabible.com offers that Bezalel lacked, from the original open
sources, reached only through existing tools).

## Context

Parabible shows how a verse is put together (clauses, subject, verb,
object). Bezalel had the words of a verse with Strong's numbers and parsing
codes, but nothing above the word. The model should get it without a new
tool: the conversation stays the interface, and `lookup_verse` is already
the call for "this verse in the original".

Two open sources have clause-level syntax for the whole Bible:

- ETCBC's BHSA (Hebrew only): CC BY-NC 4.0, no Strong's numbers, its own
  Text-Fabric format with discontinuous phrases (our reader can't take it),
  and nothing for the New Testament.
- Clear-Bible's MACULA Hebrew (WLC) and MACULA Greek (SBLGNT): CC BY 4.0,
  Strong's number, lemma and English gloss on every word, explicit clause
  rules (`PP-V-S-O`) and constituent roles (`s`, `v`, `o`, `io`, `p`, `adv`,
  `pp`, `vc`, `aux`, `o2`), one "lowfat" XML tree file per chapter (Hebrew)
  or book (Greek).

## Decision

### Source: MACULA lowfat, pinned

- `Clear-Bible/macula-hebrew` at `47db250b` (HEAD on 2026-10-22):
  `WLC/lowfat/NN-Bbb-CCC-lowfat.xml`, 929 files (not the index file
  `macula-hebrew-lowfat.xml`); `Clear-Bible/macula-greek` at `8423afe4`:
  `SBLGNT/lowfat/NN-book.xml`, 27 files. 956 files, 533 MB, each pinned by
  sha256 in `data/macula_files.json` (pins.json → `macula` names it: the
  list is too long for pins.json). None is a Git LFS pointer. Each file was
  checked once against the git blob sha in the commit's tree (956 of 956).
- Fetched one at a time from raw.githubusercontent.com into `work/macula/`,
  like every other download (`Bezalel.Data.Download.fetch/3`).

### What is imported, and what isn't (licences)

MACULA's LICENSE.md (both repos, read in full at the pinned commits) puts
the datasets under CC BY 4.0 ("© 2022-2024 by Biblica, Inc"), with the
attribution "MACULA Hebrew Linguistic Datasets, available at
https://github.com/Clear-Bible/macula-hebrew/" (Greek likewise). Within
them:

- Hebrew: the WLC text is public domain; the Westminster Hebrew Syntax
  (Groves Center), OpenScriptures Hebrew Bible morphology and Cherith's
  glosses (the `@english` attribute) are CC BY 4.0. **The lowfat `@gloss`
  attribute on Hebrew words is SIL's SILHA glosses** (MACULA's
  `pipelines/apply-sil-glosses` writes it from
  `sources/biblicalhumanities/sil-hebrew-annotations`, whose LICENSE.TXT is
  an SIL end-user licence, © 2020 SIL International: no sale on its own, a
  licence when given away with a commercial product, its own attribution).
  MACULA's LICENSE.md doesn't relicense it, so it is not CC BY. **The Semantic Dictionary of Biblical Hebrew data
  (`@sdbh`, `@lexdomain`, `@coredomain`, `@contextualdomain`) is "©2000-2021
  United Bible Societies. Used with permission."** That is MACULA's
  permission, not a CC grant to us.
- Greek: the SBLGNT text (LogosBible/SBLGNT at `736fdc76`, the commit MACULA
  names) is CC BY 4.0 (its LICENSE at that commit is the CC BY 4.0 legal
  code; its README says so); the `@gloss` glosses are the Berean Interlinear
  Bible's (public domain since 2023-04-30), `@english` Cherith's (CC BY
  4.0). **The Louw–Nida/MARBLE attributes (`@ln`, `@domain`) are UBS data
  "Used with permission."**

So `Bezalel.Data.Syntax` reads only the attributes it names (word: `ref`,
`role`, `after`, `strongnumberx`/`strong`, `english`, `lemma`, and in Greek
only `gloss`;
group: `class`, `rule`/`Rule`, `role`) and drops everything else. The build
report counts every attribute it saw and lists the UBS ones separately
(this build: Hebrew `sdbh`, `lexdomain`, `coredomain` 244,734 each;
`contextualdomain` does not occur at this commit; Greek `ln`, `domain`
128,616 each) and, separately, the Hebrew `gloss` (SILHA, 475,911); tests
feed them in and check they aren't stored. Other
CC BY attributes (Mandarin glosses, LXX equivalents, frames, referents,
morphology codes) are left out because the section doesn't use them, not
for licence reasons. The pack's whole content is CC BY 4.0 or public
domain; it has no NC or SA material, and its `pack_meta.licences`,
manifest entry and Credits say so.

Glosses: Hebrew uses Cherith's `english` only (16,887 Hebrew words have
none and are shown without a gloss; the first build fell back to `gloss`,
SILHA, for 13,778 of them: corrected 2026-10-22 after review); Greek the
Berean `gloss` (README: the Berean Interlinear's, public domain), else
Cherith's `english` (678 words; both licensed). They are word glosses, and the
section says "MACULA's word glosses, not a translation". Whether Cherith's
glosses are machine-made was not checked; they are never presented as a
translation.

### Shape: one JSON row per verse

`syntax_verses` has one row per verse in the packs' English numbering
(`reference` 'Psa.3.0'), with the edition's own verse(s)
(`source_reference`), the tree file(s) and `clauses`: JSON, a list of
sentences, each a list of clauses `[depth, role, rule, parts]`, a part
`[role, items]`, an item `[text, strong, gloss, lemma]`, `[verse, text]` for
words outside the verse, `[verse]` for a clause outside it, or the number of
a clause shown. Not node tables: `lookup_verse` always wants one verse's
whole structure, so one indexed read of one row is all it does, and a node
table (about 1.5 million word and group rows) would cost more in indexes
than in data.

- A clause is a `wg class="cl"`; its parts are its constituents, each the
  words of one node bringing a role (the nearest role between word and
  clause; MACULA puts roles on the clause's constituents), so two sibling
  prepositional phrases are two parts, as the rule `PP-PP` says.
- A clause's role is its own `role` only. In its parent it is filed under
  the role of the constituent it sits in, else its own (Gen 1:4's object
  clause is the parent's `[object]`). A clause with no role of its own
  inside a constituent (a relative or participial clause in a subject) is
  named "Clause in the subject", never "Subject clause". A role inside a role of the same clause (370
  in the Greek, 0 in the Hebrew) is counted and the outer kept; six Greek
  `role="err_…"` values (MACULA's conversion flags) are read as no role.
- A clause inside a clause is a numbered reference from the part it fills
  and its own line, indented. A clause made of nothing but clauses (Greek
  `ClCl`) is dissolved into them. A group at the top of a sentence (how
  MACULA joins clauses with conjunctions, rule-less in the Hebrew) is shown
  as "Joined clauses" so its conjunctions keep their place.
- Sentences across verses (1,196 of the SBLGNT's 8,010 have words in more
  than one verse; none of the WLC's, which are its verses): a verse shows the clauses with words in it and the
  clauses around them; their words outside the verse keep only their text
  (at most 8 of a run) and their verse; the sentence's other clauses are
  counted ("5 of its clauses outside it are left out"), not stored. So no
  verse repeats a twelve-verse sentence in full.
- Strong's numbers in Bezalel's form (`H0430`, `G0976`). A number with one
  of MACULA's letter suffixes is stored as none: the suffixes mark other
  words than the bare number, mostly the prefix particles (`2050b` וְ,
  `1886a` הַ, `3807a` לְ, `0871a` בְּ; bare H0871 is Atharim, H3807 'beat'),
  and no mapping to STEPBible's H9xxx prefix numbers is proven (178,270
  Hebrew words as shown, split verses counted under each, and 5 Greek ones
  have no Strong's number in the pack). (The first
  build dropped the suffix and so pointed at unrelated entries; corrected
  2026-10-22 after review.)

Size (build of 2026-10-22): 31,201 rows, 34 MB of JSON, **44.2 MB raw,
3.96 MB with `zstd -19`** (target was well under 40 MB).

### Numbering

The WLC numbers verses as the Hebrew Bible does. As the scrolls pack does,
the base core pack's `verses.reference` maps them (`Psa.3.0(3.1)`: the WLC's
Psalm 3:1 is the superscription, English 3:0). Unlike the scrolls' map, a
source verse can map to two English verses: the core pack splits some
Hebrew verses (`Psa.23.0(23.1)` beside `Psa.23.1`, `Mrk.12.15(12.14)` beside
`Mrk.12.14`), and without a word alignment we can't split the tree, so the
whole source verse is filed under each English verse and the section says
"WLC 23:1 is split between 23:0–1 in English numbering; it is shown
whole". STEP's NT `[ ]` and `{ }` references are the row's own verse. Every
source verse maps; the core pack's 18 verses without a row are Matthew
17:21, 18:11, 23:14, Mark 7:16, 9:44, 9:46, 11:26, 15:28, Luke 17:36, 23:17,
John 5:4, Acts 8:37, 15:34, 24:7, 28:29 and Romans 16:25–27 (MACULA Greek's
SBLGNT trees end Romans with a 16:24, the benediction, and have no doxology:
observed, not explained).

### In lookup_verse

- Read only under the word list's gate: the original shown
  (`include_original`, default true), and a single verse or a passage with
  `include_morphology`. Silent without the pack or with one that can't be
  read (the output is then exactly what it was; tested).
- A "Clause structure" section after the verses: it says which text the
  tree is of (the WLC or the SBLGNT, whose words can differ from STEPBible's
  Hebrew and Greek shown above), then per verse lines like
  `1. Clause (PP-V-S-O): [prepositional phrase] בְּרֵאשִׁ֖ית 'in beginning' ·
  [verb] בָּרָ֣א 'created' · [subject] אֱלֹהִ֑ים 'God' · [object] …`, roles in
  plain English, nested clauses indented, and a Source line linking the tree
  file at the pinned commit (`Citations.macula/4`, licence CC BY 4.0).
- Bounded: the whole section (intro, headings, notes, Source lines) is at
  most 4,000 Unicode code points, cut at a whole line with a note; the
  verses after the cut are left out and not cited. Over every verse of the
  Bible the single-verse section is 1,003 code points at the median, 1,534
  at the 95th percentile and 2,799 at most (Mark 12:15), so no single verse
  is cut; the cap bites for passages.
- The tool description and the prompt's guide line name the clause
  structure; nothing else in the prompt changes. No new tool, no new
  parameter, no Sources switch (it is reference data like the word list).

## Consequences

- A new optional pack `syntax` (`DB.@packs`); the apps need its manifest entry
  (`required: false`) and, in the phone app, `Packs.Manifest.@known` and a
  study-library title.
- A MACULA bump is a new `macula_files.json` and a rebuild; the publish
  refuses a pack not built from the pins, the base core pack and this code
  (`Publish.check_syntax/2`).
- The section's words are MACULA's WLC/SBLGNT, not the STEP text above them;
  they usually agree, and the section says when they might not. Not checked
  word by word against TAHOT/TAGNT.
- Not verified: the rendering on a device (the section is plain Markdown in
  the existing tool result); how the model uses it in a reply.
