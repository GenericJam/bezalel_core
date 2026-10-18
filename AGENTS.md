# bezalel_core — Agent Instructions

Bezalel's study tools, shared by the phone app (GenericJam/bezalel_mob, Mob)
and the website (bezalel_ca). Read this file before you change anything. The
phone app's AGENTS.md has the wider picture (repo topology, issue tracking
in beads, the verification ladder, adversarial review); its rules apply here
too unless this file says otherwise.

> **Keep this file up to date** in the same commit as the change it
> describes.

## What lives here, and what doesn't

- **Here:** the study tools (`Bezalel.Study.Tools.*`, `Rho.Tool` modules),
  pack access (`Bezalel.Study.DB`), reference parsing, the corpus registry,
  the genre guidance and the system prompt. Anything every Bezalel app must
  answer the same way.
- **Not here:** UI, Mob, Phoenix, settings storage, where files live on a
  device, pack downloads. The host app supplies those through config (today
  just `config :bezalel_core, :packs_dir`: a path or `{m, f, a}`). A new
  platform need gets a config key or a behaviour the app implements, never
  a dependency on the app's framework.
- Why the split: the phone app's
  `decisions/2026-10-17-study-code-in-bezalel-core.md`.

## Rules

1. **No compile-time `~r` regex in `lib/`.** A regex compiled into a module
   is tied to the OTP that compiled it; the phone app runs on another.
   Compile at run time through `Bezalel.Study.Patterns` (cached in
   `:persistent_term` under a key that hashes the sources). The pre-commit
   hook and CI reject new ones.
2. **Commit with a pathspec:** `git add <paths>`, `git diff --cached
   --stat`, `git commit -m "…" -- <paths>`.
3. **Tests that change global state are not async** (`Application.put_env`
   of `:packs_dir`, `:persistent_term`); restore what they change.
4. **New behaviour ships with a test** that would fail if the change were
   reverted.
5. **A change here is a change to every app.** Before pushing, run the phone
   app's suite against this checkout (`BEZALEL_LOCAL_DEPS=bezalel_core mix
   test` there), then bump its pin to the pushed commit.

## Before every commit

```bash
mix format
mix credo --strict
mix compile --warnings-as-errors
mix test
```

## Fixtures

`test/fixtures/packs` are cut from the real packs by the phone app's
`data/scripts/make_fixtures.py` (it writes here by default when the two
repositories are checked out side by side). Re-cut them when a test needs a
row they don't keep; the phone app's tests read them from this dependency.
