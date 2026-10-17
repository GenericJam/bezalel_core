# bezalel_core

Bezalel's study tools, shared by its apps: the phone app
([GenericJam/bezalel](https://github.com/GenericJam/bezalel), built with
Mob) and the website (bezalel_ca). Plain Elixir, with no UI and no platform
code.

- **The study tools** (`Bezalel.Study.Tools.*`): an Elixir port of
  [studybible-mcp](https://github.com/djayatillake/studybible-mcp)'s query
  layer (MIT), as [rho](https://github.com/GenericJam/rho) tool modules over
  the study packs (SQLite). See [docs/study_tools.md](docs/study_tools.md).
- **Pack access** (`Bezalel.Study.DB`): read-only, one connection per call.
  The host app names the packs directory:

  ```elixir
  # a path ...
  config :bezalel_core, :packs_dir, "/srv/bezalel/packs"
  # ... or a function resolved on every call
  config :bezalel_core, :packs_dir, {MyApp.Storage, :packs_dir, []}
  ```

- **The corpus registry, the genre guidance and the system prompt**
  (`Bezalel.Study.Ancient.Registry`, `Bezalel.Study.Hermeneutics`,
  `Bezalel.Study.Prompt`).

The packs themselves are built and published by the phone app's `data/`
pipeline; their sources and licences are in its `data/SOURCES.md`.

## Development

```bash
mix setup     # deps and the git hooks
mix test      # against the fixture packs in test/fixtures/packs
```

Agents working here: start with [AGENTS.md](AGENTS.md).
