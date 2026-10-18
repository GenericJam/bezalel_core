# The Dead Sea Scrolls pack

2026-10-18. Status: accepted (Kevin approved the scope: the major non-biblical
works and every biblical scroll, not the long tail of small fragments).

## Context

Bezalel had four Dead Sea Scrolls texts (CD, 1QS, 1QSa, 1QpHab), 44 passages
of the frozen v1 `ancient` pack, built by studybible-mcp from ETCBC/dss (the
Abegg–Bowley–Cook transcription, CC BY-NC 4.0). The works commentaries cite
most (the War Scroll, the Hodayot, 4QMMT, 11QMelchizedek, 4Q246, 4Q521…) and
the biblical scrolls' readings (4QDeutj at Deuteronomy 32:8, 1QIsaa) were
missing. The base packs are never rebuilt, so the new text is a pack of its
own, `scrolls`, built in Elixir in `data/` (`mix bezalel.data.scrolls`).

## Decisions

### Same source, same rendering, same search

ETCBC/dss at the commit the ancient pack used (v2.0.1, `47ecc173`), its
feature files pinned by sha256. `Bezalel.Data.Scrolls` ports
studybible-mcp's `_render_line` and search-index rules; built from the same
files, CD, 1QS, 1QSa and 1QpHab come out byte-identical to the ancient pack's
rows, folded search text and prefix variants (the only difference is the
sort key of CD 19–20, numbered here by position). So a new passage looks,
excerpts and searches exactly like the old ones: `[ ]` reconstruction,
corrections and removals marked, the uncertain-letter circlet, `vacat`;
reconstruction never matched by search.

### The non-biblical works: one passage per fragment, one work per manuscript

- A passage is one fragment or column as ETCBC labels it (the old works'
  passages are columns), lines numbered as ETCBC numbers them. Fragmentary
  manuscripts have no column:line grammar that maps to numbers, so the
  locator is the label and a line ('1QM 5:3', '4Q174 frg. 1–2 i 10'),
  resolved against the pack: the label's lookup key (`section_number`) and
  its position (`book_number`) give the sort key, and the overlap query is
  the old one. 'frg. 1–2 i', 'f1_2i' and '1–2 i' read as one label; a Roman
  column number as its Arabic one.
- Each manuscript is a work, cited by siglum or conventional name; the copies
  of a composition share a collection (its title), and one principal copy
  (1QM, 1QHa, 11Q19) carries the composition's title. No composite text is
  made (4QMMT's six copies stay six): a composite is an editor's
  reconstruction, and the scrolls' differences are the evidence.
- The tag: composition date, kind, tier A, the edition, and the copy's name
  and script period. Copy periods are the Leon Levy Dead Sea Scrolls Digital
  Library's (IAA), with Cross's conventional ranges (Hasmonean c. 150–30 BC,
  Herodian c. 30 BC–AD 68); none where the library has no page (1QM, 1QHa,
  11Q19: the Israel Museum's scrolls) or gives no period. Composition dates
  are the handbooks' general consensus and were not checked against one
  source; treat them as approximate.

### Which works are major

Thirty compositions, 132 manuscripts: the ones a reader of commentaries meets
by name. Evidence for each: its editio princeps (from its Leon Levy page) and
its treatment as a work of its own in the standard reference works (below).
Jubilees, Tobit, the Prayer of Nabonidus and the Targum of Job were added to
the candidate list: they are cited in Genesis, Daniel and Job commentaries
and the Qumran copies are their oldest witnesses.

| Composition | ETCBC manuscripts | Reference work | Editio princeps (Leon Levy) |
|---|---|---|---|
| Damascus Document | 4Q266–273, 5Q12, 6Q15 | EDSS [“Damascus Document”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-112) | [4Q266: Baumgarten 1996. DJD 18: 1-93](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q266-1) |
| Community Rule | 4Q255–264, 5Q11 | EDSS [“Rule of the Community”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-456) | [4Q255: Alexander, Vermes 1998. DJD 26: 27-38](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q255-1) |
| Rule of Blessings (1QSb) | 1QSb | EDSS [“Rule of the Blessings”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-455) | — |
| War Scroll (1QM) | 1QM, 4Q491–496 | EDSS [“War Scroll”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-562) | — |
| Hodayot (Thanksgiving Hymns) | 1QHa, 1Q35, 4Q427–432 | EDSS [“Hodayot”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-220) | — |
| Temple Scroll | 11Q19–21, 4Q524 | EDSS [“Temple Scroll”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-535) | — |
| Miqsat Ma'ase ha-Torah (4QMMT) | 4Q394–399 | EDSS [“Miqtsat Ma῾asei Ha-Torah”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-334) | [4Q394: Talmon with assistance of Ben-Dov 2001. DJD 21: 157-166.; Qimron, Strugnell 1994. DJD 10: 3-13](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q394-1) |
| Florilegium (4Q174) | 4Q174 | EDSS [“Florilegium”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-179); EDSS [“Eschatological Midrashim”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-157) | [4Q174: Allegro 1968. DJD 5: 53-57](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q174-1) |
| Testimonia (4Q175) | 4Q175 | EDSS [“Testimonia”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-538) | [4Q175: Allegro 1968. DJD 5: 57-60](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q175-1) |
| Melchizedek (11Q13) | 11Q13 | EDSS [“Melchizedek”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-318) | [11Q13: Garcia Martinez, Tigchelaar, van der Woude 1998. DJD 23: 221-241](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/11Q13-1) |
| Aramaic Apocalypse / Son of God text (4Q246) | 4Q246 | EDSS [“Aramaic Apocalypse”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-35) | [4Q246: Puech 1996. DJD 22: 165-183](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q246-1) |
| Messianic Apocalypse (4Q521) | 4Q521 | EDSS [“Messianic Apocalypse”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-323) | [4Q521: Puech 1998. DJD 25: 1-38](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q521-1) |
| Pesher Nahum (4Q169) | 4Q169 | EDSS [“Pesher Nahum”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-394) | [4Q169: Allegro 1968. DJD 5: 37-42](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q169-1) |
| Pesher Psalms (4Q171) | 4Q171 | EDSS [“Pesher Psalms”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-396) | [4Q171: Allegro 1968. DJD 5: 42-50](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q171-1) |
| Pesher Isaiah (4Q161-165) | 4Q161–165 | EDSS [“Pesher Isaiah”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-392) | [4Q161: Allegro 1968. DJD 5: 11-15](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q161-1) |
| Songs of the Sabbath Sacrifice | 4Q400–407, 11Q17 | EDSS [“Songs of the Sabbath Sacrifice”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-511); EDSS [“Angelic Liturgy”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-20) | [4Q400: Schuller 1998. DJD 11: 75-85.; Newsom 1998. DJD 11: 173-196](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q400-1) |
| Genesis Apocryphon (1Q20) | 1Q20 | EDSS [“Genesis Apocryphon”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-182) | [1Q20: Milik 1955. DJD 1: 86-87](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/1Q20-1) |
| Aramaic Enoch (4Q201-212) | 4Q201, 4Q202, 4Q204–212 | EDSS [“Enoch, Books of”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-153) | [4Q201: Milik 1976. BE : 139-163, 340-343.; Stuckenbruck 2000. DJD 36: 3-7](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q201-1) |
| Book of Giants | 1Q23, 1Q24, 2Q26, 4Q203, 4Q530–533, 6Q8 | EDSS [“Giants, Book of”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-186) | [1Q23: Milik 1955. DJD 1: 97-99.; Stuckenbruck 2000. DJD 36: 49-66](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/1Q23-1) |
| Aramaic Levi Document | 1Q21, 4Q213–214b | EDSS [“Levi, Aramaic”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-291) | [1Q21: Milik 1955. DJD 1: 87-91.; Beyer 1994. Die aramaischen Texte von Toten Meer. Gottingen. 71-78](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/1Q21-1) |
| Instruction (4Q415-418) | 1Q26, 4Q415–418, 4Q418a, 4Q418c, 4Q423 | EDSS [“Sapiential Work”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-469) | [1Q26: Milik 1955. DJD 1: 101-102.; Strugnell, Harrington 1999. DJD 34: 535-539](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/1Q26-1) |
| Commentary on Genesis A (4Q252) | 4Q252 | EDSS [“Genesis, Commentary on”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-181); EDSS [“Pesher Genesis”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-389) | [4Q252: Brooke 1996. DJD 22: 185-207](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q252-1) |
| Sefer ha-Milhamah (4Q285) | 4Q285, 11Q14 | EDSS [“The War Rule, Serekh ha-Milhamah, 4Q285”](https://ibiblio.org/expo/deadsea.scrolls.exhibit/Library/warrule.html); [Israel Antiquities Authority, Leon Levy Dead Sea Scrolls Digital Library, manuscript '4Q285 – 4Q Sefer ha-Milhamah'](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q285-1) | [4Q285: Alexander, Vermes 2000. DJD 36: 228-246](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q285-1) |
| Catena A (4Q177) | 4Q177 | EDSS [“Catena”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-77); EDSS [“Eschatological Midrashim”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-157) | [4Q177: Allegro 1968. DJD 5: 67-74](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q177-1) |
| Songs of the Sage (4Q510-511) | 4Q510–511 | [Joseph L. Angel, The Songs of the Sage (4Q510, 4Q511) (Brill), dedicated critical edition](https://brill.com/abstract/title/62206) | [4Q510: Baillet 1982. DJD 7: 215-219](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q510-1) |
| Copper Scroll (3Q15) | 3Q15 | EDSS [“Copper Scroll”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-102) | [3Q15: Milik 1962. DJD 3](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/3Q15-1) |
| Jubilees (Qumran copies) | 1Q17–18, 2Q19–20, 3Q5, 4Q216, 4Q218–222, 4Q223–224, 11Q12 | EDSS [“Jubilees, Book of”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-262) | [1Q17: Milik 1955. DJD 1: 82-84](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/1Q17-1) |
| Tobit (Qumran copies) | 4Q196–200 | EDSS [“Tobit, Book Of”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-547) | [4Q196: Fitzmyer 1995. DJD 19: 1-39](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q196-1) |
| Prayer of Nabonidus (4Q242) | 4Q242 | EDSS [“Nabonidus, Prayer of”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-351) | [4Q242: Collins 1996. DJD 22: 83-93](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q242-1) |
| Targum of Job (11Q10) | 11Q10, 4Q157 | EDSS [“Job, Targum of”](https://www.oxfordreference.com/display/10.1093/acref/9780195084504.001.0001/acref-9780195084504-e-249) | [11Q10: Garcia Martinez, Tigchelaar, van der Woude 1998. DJD 23: 79-180](https://www.deadseascrolls.org.il/explore-the-archive/manuscript/11Q10-1) |

EDSS: Schiffman & VanderKam (eds.), *Encyclopedia of the Dead Sea Scrolls* (Oxford University Press, 2000), on Oxford Reference; each entry page was opened on 2026-10-18. Sefer ha-Milhamah and the Songs of the Sage have no EDSS entry of their own that could be confirmed (Oxford Reference stopped answering before the alphabetical range of the latter; 4Q285 is likely treated under 'War Scroll'): the evidence there is the Library of Congress exhibition and a dedicated Brill edition. The editio princeps column is each work's first manuscript's Leon Levy page.

Borderline, kept: Catena A (4Q177; some read it as part of the same work as
4Q174) and Testimonia (one sheet). Disputed identifications are kept with a
'?' in the name (1QEnGiantsb?, 4QEnGiantse?, 4QInstructionf?, 11QTc?).

Not in ETCBC/dss, so not imported: the Masada Songs of the Sabbath Sacrifice
(Mas1k), 4Q206a (Giants), 4Q173 (Pesher Psalms b), 3Q4 (Pesher Isaiah),
4Q253–254a (Commentaries on Genesis B–D), and the Genizah copies of Aramaic
Levi. Not imported by choice: the remaining 603 non-biblical scroll nodes
(small fragments known by siglum only, and works not judged major, e.g. New
Jerusalem, 4Q448, the non-masoretic compositions of 11QPsa).

### The biblical scrolls: witnesses in compare_biblical_versions

Every word ETCBC assigns to a verse becomes part of that manuscript's
reading of the verse (11,919 readings of 8,020 verses from 262 manuscripts).
They are shown by `compare_biblical_versions` as `DSS` witnesses beside the
MT and LXX, because that tool already answers "what do the witnesses read
here", grouped by canonical verse with each edition's own numbering. Not a
new tool: the model would have to know to call it, and every comparison of
the Hebrew text should show the scrolls. Not `get_textual_variant`: that is
Heiser's curated cases with his analysis, and mixing a raw witness list into
it would blur whose judgement is whose.

- Default on, as their own source `manuscripts:dss` (a user can switch them
  off; asked for by name when off, the tool says so).
- A reading wholly inside `[ ]` says nothing legible survives; others give
  the count of letters outside reconstruction, so no one rests an argument
  on an editor's restoration.
- ETCBC numbers verses as the Hebrew Bible does; the reading is filed under
  the packs' English numbering (from the base core pack's `verses.reference`)
  and the row names the Hebrew one. One verse the MT lacks (Josh 5:0,
  4QJosha's text before 5:2) keeps ETCBC's number and says so.
- Words in fragments ETCBC couldn't place (its `book` is the siglum) have no
  verse and are left out.

### Without the pack

The pack is optional. A search of `qumran` or `all` reads the ancient pack and
says the other scrolls need the scrolls pack; a citation of a scrolls work is
the missing-pack error; `compare_biblical_versions` notes the DSS readings
need the pack (and errs only when asked for DSS alone).

### Licence

ETCBC/dss is CC BY-NC 4.0, already accepted for the ancient pack: non-commercial
use, the credit shown with every passage and reading. No English translation
of the scrolls is openly licensed; none is imported, and the caveat says any
English is the assistant's own.

## Consequences

- `search_ancient_sources` ranks two packs' bm25 scores together; each pack's
  scores are relative to its own index, so the merge is approximate.
- Adding a work is a registry entry in `Bezalel.Study.Ancient.Scrolls` and a
  rebuild of the pack (a new data version).
- The manuscript names of the biblical scrolls come from one source (Leon
  Levy), 203 of 265; the rest have only their siglum.
