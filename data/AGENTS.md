# bezalel_core/data — Agent Instructions

Builds study data in Elixir (`:bezalel_data`, depends on bezalel_core by
path). Read [README.md](README.md) first. bezalel_core's
[AGENTS.md](../AGENTS.md) applies here too unless this file says otherwise.

> **Keep this file and README.md up to date** in the same commit as the
> change they describe.

## Rules

1. **Every download is pinned by sha256** in `pins.json`. A build that gets
   different bytes stops; it never builds from them. Bumping a pin is a
   reviewed change: diff the new responses (kept as `work/**.unverified`)
   and the new `out/net_report.txt` against the old before committing it.
2. **Every table records its licence** — in README.md's table list, in
   `pack_meta.licences`, and for a translation in its `translations` row
   (`copyright`, `licence`). A source whose licence doesn't allow the use
   isn't imported. NET: the verse text only; the NET translators' and study
   notes are not licensed and must never be imported. Scrolls: ETCBC/dss is
   CC BY-NC 4.0 (non-commercial, credit shown); no English translation of
   the scrolls is openly licensed, so none is imported.
3. **Text is not altered.** Markup is removed and whitespace collapsed;
   small capitals become capitals. Anything else the source sends that isn't
   verse text (headings, labels, notes) is dropped by a rule naming its
   markup, never by matching words, and the report lists what was dropped.
   Unknown markup stops the build. Scrolls: the text is ETCBC's signs with
   its editorial marks rendered as studybible-mcp did (`Bezalel.Data.Scrolls`);
   what is left out is left out by a feature or sign-type rule and counted in
   `out/scrolls_report.txt`; an unknown sign type stops the build.
4. **Nothing built is committed** except the fixtures in
   `../test/fixtures/packs/` (`mix bezalel.data.fixtures`). `out/`, `work/`,
   `_build/` and `deps/` are gitignored; the parent repo's pre-commit hook
   rejects other `*.sqlite`.
5. **No compile-time `~r` regex in `lib/`**: compile with
   `Regex.compile!/1` at run time, as core does (its rule 1).
6. **Tests use small inline inputs, no network**, and pin the behaviour that
   matters (book codes, what is dropped, superscriptions, small caps).
7. **The base is never republished.** `base.json` pins the five v1 packs;
   `mix bezalel.data.publish` copies their entries unchanged and uploads only
   packs built here. Replacing a base pack is a deliberate change to
   `base.json` (and costs every phone that download). Publishing needs
   wrangler logged in to the bucket's Cloudflare account; agents run only
   `--dry-run`.

## Before every commit

```bash
mix format
mix credo --strict
mix compile --warnings-as-errors
mix test
```

Re-run `mix bezalel.data.net` / `mix bezalel.data.scrolls` and `mix
bezalel.data.fixtures --pack <pack>` when an importer changes, and run
core's suite (`cd .. && mix test`) when a fixture changes. Which Dead Sea
Scrolls are imported is core's `Bezalel.Study.Ancient.Scrolls`: a work added
there is imported by the next `mix bezalel.data.scrolls`.
