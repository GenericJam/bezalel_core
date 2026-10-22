# The UBS dictionaries pack

2026-10-22. Status: accepted (bead `bezalel-bsw.5`, epic `bezalel-bsw`: the
data parabible.com offers that Bezalel lacked, from the original open sources,
through existing tools only).

## Context

`word_study` gave BDB (Hebrew), LSJ and Abbott-Smith (Greek) and STEPBible's
semantic range, but no sense-by-sense analysis by semantic domain. The United
Bible Societies publish two such dictionaries under CC BY-SA 4.0 in
[ubsicap/ubs-open-license](https://github.com/ubsicap/ubs-open-license): the
UBS Dictionary of Biblical Hebrew (extracted from the Semantic Dictionary of
Biblical Hebrew, SDBH) and the UBS Dictionary of the Greek New Testament (a
revised Louw & Nida). Each entry carries Strong's codes in the packs' own form
(`H0003`, `G0026`, Aramaic `A0004`), so they join the core lexicon without
Macula.

## Decisions

### Source and edition

The commit `a15a96cf` (2026-10-21, Hebrew v0.9.4; the repository has no tags
and is still updated), pinned by sha256 per file. English only. The JSON
editions, read with Jason: the Greek JSON is v1.1, the XML v1.0 only, and v1.1
is v1.0 plus 18 English senses, a few corrected definitions and glosses, and
parts of speech (compared entry by entry); the two lexical-domain files are
byte-identical. The contextual-domain file isn't used (no meaning refers to it
by design; see below).

### One pack, keyed by the core lexicon's Strong's numbers

A new optional pack, `dictionaries`, with both dictionaries; each dictionary's
licence and verbatim attribution in its `dictionaries` row. Every Strong's code
an entry gives is normalised to the core lexicon's key: `A0004` → `H0004`
(Strong's numbers Aramaic words in the Hebrew range; checked: UBS `A1668`
דָּא, `A6640` צְבוּ are the core's `H1668`, `H6640`), a letter suffix
(`H0032b`, `G0518a`) is dropped, and the two bare codes (`2062`, `6859`) get the
dictionary's prefix. A compound name's code (`H0410+H1285`, El-Berith; 6
entries) keys nothing: neither number alone is that name. Entries with no usable
code — 38 Hebrew, 110 Greek (mostly proper names and letters) — are in the pack
but unreachable by Strong's; 565 Hebrew keys aren't in the core lexicon (e.g.
`H0136` אֲדֹנָי), so `word_study` can't reach those either (it errors on a number
the core lexicon lacks, as before). The report lists them.

### What is stored

Per meaning: id, part of speech, Louw–Nida number (Greek), domains and
subdomains (codes; names from the lexical-domain files), SDBH's source domain,
short definition, glosses, comments and the number of references UBS lists.
The references themselves (291,411 Hebrew, mostly word-level; 130,923 Greek)
are not imported: no tool shows them, and they would roughly double the pack
(9.9 MB now, 1.6 MB with `zstd -19`). A sense marked `AIGenerated` is not
imported (none at this commit), so machine-made English is never shown as
UBS's.

Markup is rendered by named rules (links → their text, `{D:}` → `LN n`, `{S:}`
→ STEP references in the packs' English numbering through the base core pack,
`{A:}` → the abbreviation, footnote markers dropped, `|i…|i*` → text, `|` in
comments → a space), counted in the report; anything else stops the build. One
comment has a malformed `{D:6.149)`; a rule names it. The NT's alternative
numbers in the core pack (`Php.1.16[1.17]`) are dropped before mapping: UBS's
NT numbering is the packs' (checked on Php 1:17, which the build otherwise
couldn't place).

### Domain names: the domain file decides

14 Hebrew meanings name a top-level lexical code (001 Objects, 002 Events, 003
Reference) with a contextual domain's label (Ability, Abundance, Access), and 3
name a source domain that way: an upstream slip. Both labels would mislead, so
those domains are left out and listed in the report.

### word_study: appended, bounded, silent without the pack

After the core lexicon entry and its Source line, `word_study` appends each UBS
entry for the number (at most 3, the rest counted): its meanings (at most 10 and
about 3,000 characters an entry, as `Format.lexicon_entry/1` cuts a full
definition; the cut is said), each with its domain(s), definition, glosses,
reference count and Louw–Nida's note cut at 300 characters, and a Source line.
Without the pack, or with one whose tables can't be read, nothing is added (the
`add_notes_hints` pattern): the output is the same as before, which a test
pins. `search_lexicon` and `search_by_strongs` are unchanged: a search by
meaning would be a new query interface, which the epic rules out.

### Citations

Neither dictionary has a page per entry online (sdbh.org and
semanticdictionary.org now redirect to marble.bible, an app with no entry
links; checked 2026-10-22), so a record cites the dictionary's JSON file on
GitHub at the pinned commit; the credits link UBS's pages for each dictionary
(translation.bible) and the repository.

## Consequences

- The phone app needs `dictionaries` in `Packs.Manifest.@known`, a study
  library title and SOURCES.md entries (proposed in the slice report); the
  website takes it from the manifest.
- A new UBS commit is a reviewed pin bump: rebuild, diff the report.
- Verified: the build from the pinned files; `word_study` against the real
  pack for G0026, H7307, H0430 and H2452. Not verified: the pack on a phone
  (it is plain SQLite, no FTS); whether UBS's NT numbering differs from the
  packs' anywhere the text cites (the build would stop on a verse the core
  pack lacks, and didn't).
