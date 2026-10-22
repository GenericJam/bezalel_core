# The witnesses pack

2026-10-22. Status: accepted (beads `bezalel-bsw.2`, `bezalel-bsw.3`).

## Context

Parabible offers the Samaritan Pentateuch, the SBL Greek New Testament and
text-critical data Bezalel lacked. Kevin asked for them built from the
original open sources, reached only through the existing tools.

## Decision

One optional pack, `witnesses`, four sources, each in tables of its own
with its licence (`witness_sources`):

- **Samaritan Pentateuch**, DT-UCPH/sp Text-Fabric 7.2.4 (CC BY-NC 4.0;
  Højgaard, Naaijer & Schorch 2023, doi:10.5281/zenodo.7734632): per
  verse `g_cons_utf8` + `trailer`, the dataset's own number kept, mapped
  to English with the base core pack. `Bezalel.Data.TextFabric` now takes
  DT-UCPH's `@licence=` spelling and a corpus without `line` nodes
  (`types/2`); the scrolls build is unchanged (rebuilt before and after:
  identical SQL dump and report; only `build_sha256` differs, because
  `text_fabric.ex` is one of its build inputs).
- **SBLGNT** text and **apparatus**, Faithlife/SBLGNT `c4d241a` (CC BY
  4.0). Apparatus notes parsed by the grammar the SBLGNT introduction
  gives (sblgnt.com, "Symbols Used in the Notes"); the one note outside it
  is kept raw and shown as such, not guessed at. Sigla meanings from the
  same introduction and Logos's 2013 update (NA28 cited throughout).
- **HOTTP**, ubsicap/ubs-open-license `a15a96c` (CC BY-SA 4.0), English
  fields only; the rating and factor glossaries parsed from its two
  introduction pages.

Tools (no new ones):

- `compare_biblical_versions` adds `SP` (source `manuscripts:sp`, the DSS
  pattern) and answers New Testament references, which it refused, with
  `TAGNT` (the core pack's Greek, labelled as STEPBible's *amalgamated*
  text: its header says "All the words from standard Greek editions
  (NA27/28, TR, SBL, TH, Byz, WH, Treg)"; the core pack has Matt 17:21 and
  John 1:18's "ὁ μονογενὴς θεὸς", so it is not one edition) beside
  `SBLGNT`. The NT is grouped by the core pack's chapter/verse columns:
  every SBLGNT verse is a core verse (checked by the build).
- `get_textual_variant` adds HOTTP and the apparatus after the notes
  cases; the committee's rating and factors are a section of their own,
  "its conclusion, not manuscript evidence". A verse without a notes case
  now returns these.
- `lookup_verse` hints at them.

## Consequences

- Three licences in one pack: the CC BY-NC SP is never in a table with the
  CC BY-SA HOTTP; each citation and edition line names its own.
- The SP verse citation links the dataset at the pinned commit (it has no
  per-verse page; checked: no web URL in its Text-Fabric app config). HOTTP
  links the raw XML (GitHub won't display an 8.6 MB file), naming the
  entry id. SBLGNT and the apparatus link their file's line.
- Notes I wrote from comparing the texts (not from the dataset): SP Exodus
  26:35 holds the MT's 30:1–10; SP Deuteronomy 34:1 replaces 34:1b–3.
- The SBLGNT text keeps its ⸀ ⸂ ⸃ marks (they point to the apparatus).
- Not verified: HOTTP's `*` before some base-translation renderings (kept
  as given; its meaning isn't in the introduction); whether "em" always
  belongs to the following siglum (true in all 3 notes).
- `get_textual_variant` still needs the notes pack; with only the witnesses
  pack it errs as before.
