# The Apostolic Fathers pack

2026-10-22. Status: accepted (bead `bezalel-bsw.4`).

## Context

Parabible offers the Apostolic Fathers in Greek with an English translation;
Bezalel had none of them. The study tools reach new data only through the
existing tools (no new tool, no new query interface), so the Fathers had to
come in as an ancient-source corpus that `search_ancient_sources` and
`lookup_ancient_source` already read, built from the original open sources,
not Parabible's API.

## Decisions

### Sources

- **Greek**: [jtauber/apostolic-fathers](https://github.com/jtauber/apostolic-fathers)
  `texts/` at `a07f9207`, Kirsopp Lake's text (Loeb, 1912–1913) compared
  against the Perseus/OGL, CCEL and Logos texts and checked twice against
  scans of the printed Lake by James Tauber and Seumas Macdonald (README,
  NOTES.md): *Open Apostolic Fathers* 1.0, Zenodo
  [doi:10.5281/zenodo.2555673](https://doi.org/10.5281/zenodo.2555673)
  (record: version 1.0, 2019-02-01, CC BY-SA 4.0). `texts/` last changed on
  2019-01-31 (`e155157`), before the v1.0 tag (`4b91432`, 2019-02-02), so the
  pinned files are the archived release's.
- **English**: [jcuenod/CAFE](https://github.com/jcuenod/CAFE) at
  `06b19aec`, the *Contemporary Apostolic Fathers Edition* by James Cuénod
  (2024), CC BY-SA 4.0 (LICENSE; README).
- **Not used**: jcuenod/tagged-apostolic-fathers (lemmas and parts of speech):
  the GitHub API reports no licence and its README's to-do list says one is
  still to be added. Parabible's "CC BY-SA 4.0 for the Text (not the
  Tagging)" is this.

Every file is pinned by sha256 in `data/pins.json` → `fathers`.

### How the English was made, and how it is labelled

Verified from the repository, 2026-10-22:

- README: "these first drafts were generated using GPT-4o"; a LaBSE
  similarity check flagged nothing in the 15 most dissimilar lines; "There
  are bound to be errors".
- `scripts/translate.py` ("to preserve the prompt and pipeline"): each Greek
  or Latin line sent to `gpt-4o-2024-05-13` with a six-message window and the
  instruction to translate into "readable, and idiomatic modern English … a
  6th grade reading level".
- History (15 commits): two change the text by hand, one line each
  (`6b5627a`, 1 Clem 0.1 "multiplied"; `74db712`, Did. 4.3 as a command).
  No other revision. Issue #1 is an "AI Proof Reader" list of open problems.

So it is a machine translation, published without systematic human revision.
It is never shown as a published human translation:

- each row's `translation`: "CAFE, Contemporary Apostolic Fathers Edition
  (James Cuénod, 2024): a machine translation, GPT-4o's first drafts
  (gpt-4o-2024-05-13) published without systematic human revision; not a
  published human translation" (the sources line under every result);
- each tag's edition: "Lake's Greek, corrected (Tauber–Macdonald); CAFE
  machine-translated English";
- the corpus caveat (always shown) says it and asks the model to say so when
  quoting;
- each passage's citation is a new kind, `Citation.translation: :machine`,
  whose Source line reads "(machine translation: AI-generated English, not a
  published human translation; say so when you quote it; original: [Lake's
  Greek line])". Neither existing kind fit: `:published` reads as a human
  translation, `:assistant` says the English is the model's own, and
  `:unpublished_draft` is the HLT's;
- the prompt's guide line for `search_ancient_sources`.

The phone app's sources view and the website's citation list key on the
`translation` value; until they handle `:machine` the website shows its
"Unpublished draft rendering" mark and the phone app none (the Source line
the model reads says it either way). The apps need a clause each.

### Links

A passage's link is its line in CAFE's file at the pinned commit
(`github.com/jcuenod/CAFE/blob/06b19aec…/011-didache.en.txt#L87`), its
original Lake's line in jtauber's (`…/texts/011-didache.txt#L87`); both
answered 200 (curl, 2026-10-22). CAFE translated the Greek files line by line
and the import checks the two have the same references in the same order, so
one line number serves both. The reader sites were not used: jtauber's HTML
has no verse anchors, and CAFE's anchors only verses after the first and
repeat chapter anchors across the Shepherd's books.

### Numbering and works

One passage per verse (Lake's chapter.verse), cited as the handbooks cite
them: 'Didache 9.1', '1 Clement 5.4', 'Ignatius, To the Ephesians 20.2'
('Ign. Eph. 20.2'), 'Polycarp, To the Philippians 10.1', 'Martyrdom of
Polycarp 9.3', 'Diognetus 5.5'. Chapter 0 is the title or salutation. The
Ignatian letters carry Ignatius' name in every name, so 'Romans 5.1' stays no
ancient work.

The Shepherd's file numbers its 27 books continuously; it is three works,
'Hermas, Vision 1–5', 'Mandate 1–12', 'Similitude 1–10', each
book.chapter.verse ('Hermas Vision 1.1.1', 'Mandate 4.1.1', 'Sim. 9.30.3').
The continuous chapter numbering (Herm. 1–114) is not supported.

Left out by rule and listed in `out/fathers_report.txt`: Lake's section
titles (the Shepherd's `<book>.0.0`, 27, and the Martyrdom's `EP.0`, the
Latin heading of the Moscow epilogue) and the two subscriptions `SB.1` (the
manuscripts' closing titles of 1 Clement and Barnabas, outside the
numbering). The Moscow manuscript's epilogue to the Martyrdom (`EP.1–5`) is
a work of its own, 'Martyrdom of Polycarp, Moscow epilogue 1'.

Papias and Quadratus are not in the source, so not in the corpus.

Greek and English references: all 1,975 lines of the 15 files match, same
references in the same order (the build stops otherwise). 1,945 passages, 38
of them Latin (Polycarp, To the Philippians 10–12 and 14; most of Hermas,
Similitude 9.30–10.4), labelled Latin.

### Search

The ancient pack's schema, FTS5 columns and tokenizer, unchanged (shared
from `ScrollsPack.ancient_schema/0`). The Greek is folded with core's
`Bezalel.Study.Ancient.Passages` (editorial signs dropped, marks and case
folded), which reproduces the ancient pack's `original_text_folded` for all
10,205 Josephus and Philo rows; the English is the `text` column, stemmed by
the tokenizer.

`search_ancient_sources` now reads "the packs of the works in scope" instead
of the hard-coded scrolls pack: the corpora in scope (the one asked for, or
every one switched on) name their works' packs (ancient, scrolls, fathers).

- With the ancient pack, every other pack in scope that is on the device,
  readable and has passages in scope is searched; one that isn't is left out
  and named in a note per pack (the scrolls note unchanged). New: a scrolls
  pack with an empty passages table is now noted too (it was searched
  silently).
- Without the ancient pack, the other packs in scope are searched and the
  note names what was searched ("only the Dead Sea Scrolls and the Apostolic
  Fathers were searched"); a damaged or empty one is the error naming the
  missing ancient pack, as for the scrolls pack before. None there: the
  missing-pack error.
- A search of `apostolic_fathers` alone needs only the fathers pack; without
  it, `DB.missing(:fathers)`. `lookup_ancient_source` needed no change
  (`Ancient.pack/1`); a citation of a Father without the pack is
  `DB.missing(:fathers)`.

The scrolls tests are unchanged and pass.

### Dates, tiers, status

Dates are ranges with their source, from Bart D. Ehrman's introductions,
*The Apostolic Fathers* (Loeb Classical Library 24–25, Harvard, 2003),
opened on loebclassics.com on 2026-10-22:

| Work | Tag | Ehrman's words |
|---|---|---|
| 1 Clement | c. AD 95–96 traditionally; limits c. 64–170 | "it appears best to assume a date sometime near the end of the first century, possibly, as traditionally thought, in the mid 90s" (LCL 24, p. 25) |
| 2 Clement | mid-2nd c., possibly the 140s | "written some time in the middle part of the second century, possibly in the 140s" (p. 160) |
| Ignatius | c. AD 110, under Trajan | Eusebius places the martyrdom "midway through the reign of Trajan (98–117 ce)"; later redatings unpersuasive to most (pp. 205, 207) |
| Polycarp, Philippians | c. 110–135 | Harrison's two letters, ch. 13 c. 110 and chs. 1–12 "some twenty or twenty-five years later", the majority view (pp. 328–329) |
| Martyrdom | 155/156; or late 160s, 177 | "probably the majority of scholars favor" 155 or 156 (p. 363) |
| Didache | c. 100, a decade or so later | "sometime around the year 100, possibly a decade or so later"; the two-ways source perhaps mid-1st c. (p. 411) |
| Hermas | perhaps 110–140 | "perhaps 110–40 ce" (LCL 25, p. 169) |
| Diognetus | 150–310; probably later 2nd c. | "sometime between 150 and 310" … "during the second half of the second century" (pp. 126–127) |
| Barnabas | c. 130 | Ehrman, "The Epistle of Barnabas in a Nutshell", Ehrman Blog (the Loeb page could not be opened); Britannica: "possibly as late as 130". After AD 70 from Barn. 16.3–4 (the temple destroyed) |

Tiers (`Registry`: A before or alongside the NT, B after it to c. AD 200):
`A/B` for 1 Clement and the Didache, the two works generally dated before c.
100 and disputed (Welborn argues 1 Clement before 70; Britannica dates the
Didache to the 2nd c.); `B` for the rest. Diognetus may be later than 200;
its date says so.

Status: "Not Scripture" (a scripture label, switchable), naming neutrally the
codices that copied a work with the New Testament, from the British
Library's catalogue: Codex Alexandrinus (Royal MS 1 D VIII) has Revelation
then 1 Clement and 2 Clement 1.1–12.5; Codex Sinaiticus (Add MS 43725) has
Revelation, Barnabas, then Hermas, incomplete (to Mandate 4.3.6 by a
secondary table; the London leaves end at Herm. 30.3).

Not verified: Holmes's *Apostolic Fathers* (3rd ed.), the Cambridge
Companion and the ODCC could not be opened; Ehrman's Loeb Barnabas
introduction; the Sinaiticus end of Hermas from a primary source.

### Licence

Both CC BY-SA 4.0, in a pack of their own (`pack_meta.licences`, every row's
`license`, `original_license`, `translation_license`); nothing CC BY-NC is
mixed in. Credited with every passage (sources line) and in
`Bezalel.Study.Credits`. The source `ancient:apostolic_fathers` is automatic
and on by default like every corpus.

## Consequences

- A small optional pack: 5.8 MB raw, 0.96 MB with `zstd -19`.
- `search_ancient_sources` over `all` ranks three packs' bm25 scores together;
  each pack's scores are relative to its own index, so the merge is
  approximate (as with the scrolls).
- English searches match CAFE's wording only: 'two ways' finds Barnabas 18.1,
  whose CAFE English says "two ways", not Didache 1.1, which says "two paths";
  the Greek 'ὁδοὶ δύο' finds both.
- Any change to the registry, `Passages` or `Ancient` changes the scrolls and
  fathers packs' `build_sha256`, so both are rebuilt before a publish (their
  rows don't change).
- The apps must handle `Citation.translation: :machine`.
