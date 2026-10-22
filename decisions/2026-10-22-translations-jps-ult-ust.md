# JPS 1917, ULT and UST in the translations pack

2026-10-22. Status: proposed (bead `bezalel-bsw.1`, epic `bezalel-bsw`: the
data parabible.com offers that Bezalel lacked, built from the original open
sources, reached through the existing tools).

## Context

The tools quoted two English translations: the NET (translations pack) and
the BSB (core pack). Parabible also offers the JPS 1917 and unfoldingWord's
ULT and UST. They are openly licensed, but partial: the JPS is the Old
Testament only, and a ULT/UST release holds only the books unfoldingWord has
finished (v91: no Numbers, 1–2 Chronicles, Ecclesiastes, Isaiah, Jeremiah,
Ezekiel). Until now a verse missing from the chosen translation fell back
silently to STEPBible's word gloss, which would have made a JPS John 3:16 a
`[gloss]`.

## Decisions

### Three more translations in the same pack, under keys `jps1917`, `ult`, `ust`

No new table and no new tool: rows in `translation_verses` and
`translations`, entries in `Bezalel.Study.Translations` (so
`Preferences.translation` accepts the keys and the apps' translation list
grows). The NET rows are byte-for-byte those of the published pack (checked:
all 31,201 rows and the `translations` row equal; same `net_sha256`). The
build task is now `mix bezalel.data.translations` (it replaces `mix
bezalel.data.net`, which wrote the same pack with the NET alone).

### Sources, pinned

- JPS: eBible.org's `engjps_usfm.zip` (public domain; its `copr.htm` says so
  and the build checks), pinned by sha256: its URL isn't versioned. Sefaria's
  copy is an API with nothing to pin.
- ULT/UST: Door43 `unfoldingWord/en_ult` and `en_ust` at tag v91 (commits
  `35d21595…`, `85f274a7…`), every book file plus LICENSE.md and
  manifest.yaml pinned by sha256.

### Versification

The packs are keyed in English numbering. eBible's JPS is already English,
with the Hebrew numbers written inline (`(3-2)`). Those are removed; where
the base core pack's `verses.reference` numbers a Hebrew verse as English
verse 0 (`Psa.3.0(3.1)`), its text becomes the Psalm's verse 0, as the NET's
titles are. Everything else keeps eBible's English verse, including where
the core places the Hebrew number elsewhere (the Decalogue's accentuation;
listed in the report). The base core pack is read through the new
`Bezalel.Data.Download.base_core!/1`, moved out of the scrolls task so the
other packs of the epic share it. ULT/UST are English (`ufw`); their `\d`
titles become verse 0.

### What is dropped, by markup only

The alignment (`\zaln-s/e`, `\w …|…`), milestones (`\ts`), footnotes (`\f`),
header lines and headings (`\s1 \sr \r \ms1 \qa \sp`); unknown markup stops
the build (`Bezalel.Data.Usfm`). Following data rule 3 (never by matching
words), the JPS keeps the words eBible's USFM has as plain text: book
openings in capitals and the Psalter's book headings ("BOOK II For the
Leader…"). A UST verse bridge (`\v 4-5`) is kept whole on its first verse.

### Licences and naming

Each translation keeps its own `licence` and `copyright` on its own rows;
`pack_meta.licences` names all three regimes (NET non-commercial by
permission, JPS public domain, ULT/UST CC BY-SA 4.0). Stripping the
alignment makes the ULT/UST text a derivative; their LICENSE.md requires a
derivative to remove the unfoldingWord® trademark (and says the name needs
written permission), state the changes, credit "The original work by
unfoldingWord is available from unfoldingword.org/ult" and stay CC BY-SA. So
the names shown are **"Literal Text (ULT, adapted)"** and **"Simplified Text
(UST, adapted)"** (abbreviations ULT, UST), and the `copyright` is the
derivative's notice. The name "unfoldingWord" appears only inside the
required attribution sentence and the original's copyright line. These
strings are written once, in core's `Translations`; the importer reads them.

### A book the translation lacks is quoted from the BSB, with one note

`Translations` records which books each translation has (`books`: `:all`,
`:old_testament`, or `:released`, asked of the pack through the primary-key
index). `Verses.attach_english/3` gives a verse in a missing book the BSB's
text and marks it (`text_fallback`, view `fallback`); `Translations.settle/3`
adds one note naming the translation and why ("The JPS 1917 covers the Old
Testament only; New Testament verses are quoted from the BSB."). If every
quoted verse is such a verse, the result's translation is the BSB (label,
card and links); in a mixed list (a ULT word study with an Ezekiel example)
each BSB verse is labelled "(BSB)" and links Bible Hub. Cross-references
link such books' verses to the BSB. A verse missing inside a book the
translation has stays the marked gloss, as for the NET (a translation's own
omission is not filled from another). A translations pack published before
these keys gives the BSB with a note that the pack needs updating.

### Links

- JPS: eBible's chapter page at the verse, `ebible.org/engjps/GEN01.htm#V1`
  (checked: 200, verse anchors present; a Psalm title is in verse 1).
- ULT/UST: Door43's reader of the imported release,
  `preview.door43.org/u/unfoldingWord/en_ult/v91/?book=tit#tit-1-5`. It
  answers 200 but draws the text by script behind a bot check; checked in a
  browser that it renders the book and scrolls to the verse (Titus 3:5, 1
  Peter 2:24). No static per-verse page of the ULT/UST was found (eBible and
  the Free Use Bible API don't carry them).

## Consequences

- The translations pack grows from 5.8 MB to 20.6 MB raw (1.5 MB to 4.9 MB
  with `zstd -19`).
- The phone app's Settings must offer five translations (a list rather
  than a segmented control) and its study library title and SOURCES.md
  change; the orchestrator does that in bezalel_mob.
- Prompt rule 5 and the `lookup_verse` description no longer name "NET or
  BSB": the label is whatever the tool gives.

## Verified / not verified

Verified: the build from the pins; NET rows unchanged; every JPS row is a
BSB reference (54 Psalm titles fused with verse 1 in eBible have no row of
their own); ULT/UST coverage against the BSB per book (reports in
`out/translations_report.txt`); the tools against the real packs (JPS
Genesis 1:1, JPS John 3:16 → BSB with note, ULT Isaiah 53:5 → BSB with note,
UST Psalm 23, a ULT word study, ULT cross-references); the link targets.

Not verified: that unfoldingWord would read "Literal Text (ULT, adapted)"
as free of their trademark (the abbreviation ULT is kept; the trademark is
the word unfoldingWord®); the eBible zip staying unchanged (sha256-pinned,
so a change stops the build).
