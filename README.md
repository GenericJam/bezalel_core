# bezalel_core

The study engine behind Bezalel, a free Bible-study companion: 25 study
tools over SQLite study packs, written in Elixir as
[rho](https://github.com/GenericJam/rho) agent tools. Every Bezalel app runs
the same engine, so a question gets the same evidence wherever it's asked:

- the phone app, [bezalel_mob](https://github.com/GenericJam/bezalel_mob)
  (Android and iOS, built with [Mob](https://github.com/GenericJam/mob));
- the website, bezalel_ca (in progress);
- later, a desktop app.

There is no UI and no platform code here.

## Credit

The study tools are an Elixir port of
**[studybible-mcp](https://github.com/djayatillake/studybible-mcp)** by
[@djayatillake](https://github.com/djayatillake) and the Study Bible MCP
contributors (MIT): its query layer, tool handlers,
output formats, tool descriptions, hermeneutics guidance, system prompt and
research-sources catalogue, ported from commit `38cef28` and adapted. The
study database those tools read is built by studybible-mcp's pipeline from
STEPBible, BibleAquifer, ACAI, Theographic, Perseus and the other sources
listed in bezalel_mob's
[data/SOURCES.md](https://github.com/GenericJam/bezalel_mob/blob/master/data/SOURCES.md).
See [NOTICE](NOTICE) for the licence text. If you want an MCP server for
Claude or another client rather than an Elixir library, use studybible-mcp.

## The tools

| Pack | Tools |
|---|---|
| core | `lookup_verse`, `word_study`, `search_lexicon`, `search_by_strongs`, `get_cross_references`, `parse_morphology`, `lookup_name`, `find_similar_passages`, `get_torah_weave` |
| graph | `people_in_passage`, `explore_genealogy`, `explore_person_events`, `explore_place`, `find_connection`, `graph_enriched_search` |
| notes | `get_study_notes`, `get_bible_dictionary`, `get_key_terms`, `get_ane_context`, `get_theology_context`, `get_textual_variant` |
| lxx | `compare_biblical_versions` (with core; the scrolls pack adds its DSS witnesses) |
| translations | the NET text the verse tools quote (the BSB is in core) |
| ancient | `search_ancient_sources`, `lookup_ancient_source` |
| scrolls | the Dead Sea Scrolls: 30 major non-biblical works (132 Qumran manuscripts) for the ancient tools, and the biblical manuscripts' readings for `compare_biblical_versions` |
| none | `list_research_sources` |

Each tool is a `Rho.Tool` module (`Bezalel.Study.Tools.*`; `Bezalel.Study.Tools.all/0`
lists them) whose `run/2` returns the Markdown the model reads, and whose
`result/1` returns the same answer as data for an app to draw. A missing pack
is an error that names it, so the model can say so instead of guessing.
How each was ported and where it differs from studybible-mcp:
[docs/study_tools.md](docs/study_tools.md).

Also here: `Bezalel.Study.Reference` (book names and reference forms),
`Bezalel.Study.Ancient.Registry` (the ancient-source corpora and their
labels), `Bezalel.Study.Hermeneutics` (genre guidance),
`Bezalel.Study.Preferences`, `Bezalel.Study.Sources` and
`Bezalel.Study.Translations` (a user's settings, the sources they can switch
off, the translations they can pick) and `Bezalel.Study.Prompt` (the system
prompt).

And the agent's surface, the same for every app that shows a conversation:
`Bezalel.Agent.Reply` folds rho's loop events (`Rho.Events`) into the
reply's blocks (THINKING, TOOL CALL, SUMMARY) as it streams,
`Bezalel.Agent.Card` builds the passage card from `lookup_verse` /
`word_study` data, and `Bezalel.Library.Transcript` reads a conversation's
messages (`Bezalel.Library.Message`) back off its rho session and plans the
branch moves behind Delete and Undo. None of it reads or writes a file:
the app keeps the state, draws it, and reads and writes the session file.

And **materials**, the files sent to the agent and received from it (photos,
audio, video, documents, and their transcripts, audio tracks, stills and
drawings): `Bezalel.Materials` names each by the SHA-256 of its bytes, says
what goes to a model (pictures and PDFs by reference, audio and video as
their transcript), and resolves rho's attachment references through the
app's store; the `draw_image` tool (`Bezalel.Study.Tools.materials/0`)
draws with OpenAI's gpt-image on the user's API key; `Bezalel.Speech` turns
a reply into words for text-to-speech. Where the files live stays the
app's.

## Using it

```elixir
# mix.exs — unreleased, so pinned to a commit
{:bezalel_core, github: "GenericJam/bezalel_core", ref: "<commit>"}
```

Tell it where the packs are, as a path or a function resolved on every call:

```elixir
config :bezalel_core, :packs_dir, "/srv/bezalel/packs"
config :bezalel_core, :packs_dir, {MyApp.Storage, :packs_dir, []}
```

Tell it where a user's study settings come from (approach, scripture labels,
switched-off sources, default result count, translation), as a function
called on every tool call with the tool's ctx appended (it carries
`:session_id`); unset, everyone gets the defaults:

```elixir
config :bezalel_core, :preferences, {MyApp.Settings, :study_preferences, []}
# MyApp.Settings.study_preferences(ctx) returns a map or %Bezalel.Study.Preferences{}
```

Give the tools to a rho loop, withholding those whose sources the user
switched off, with the system prompt for the same settings (`surface`: your
app's own section on how answers are displayed):

```elixir
prefs = Bezalel.Study.Preferences.current(%{session_id: session_id})
Rho.Supervisor.start_link(tools: Bezalel.Study.Tools.all())

Rho.start_loop(
  system_prompt: Bezalel.Study.Prompt.system_prompt(prefs, surface: my_formatting_text),
  tools: :registry,
  withhold_tools: Bezalel.Study.Tools.withheld(prefs)
)
```

Keep materials: a `Bezalel.Materials.Store` of your own (every callback gets
a ctx with `:session_id`, so a host with several users finds the owner), and
rho's resolver pointed at it, then offer `draw_image` too:

```elixir
config :bezalel_core, :materials, MyApp.MaterialStore
config :rho, :resolve_attachment, {Bezalel.Materials, :resolve, []}

Rho.Supervisor.start_link(tools: Bezalel.Study.Tools.all() ++ Bezalel.Study.Tools.materials())

# Sending a question with materials (Rho.Models.inputs/1: what the model takes):
case Bezalel.Materials.attachments(materials, Rho.Models.inputs(model), %{session_id: id}) do
  {:ok, attachments} -> Rho.Loop.prompt(loop, text, attachments)
  {:missing, untranscribed} -> transcribe_then_retry(untranscribed)
end
```

Show `Bezalel.Materials.video_notice/0` before a video is sent, and read a
reply aloud with `Bezalel.Speech.speakable(summary)`. How it all works:
[docs/study_tools.md](docs/study_tools.md#materials-drawings-and-read-aloud).

The NET Bible (the default translation) is quoted by permission for
non-commercial use: show `Bezalel.Study.Translations.get("net").copyright`
with your attributions. How the settings work:
[docs/study_tools.md](docs/study_tools.md#preferences).

The packs (`core.sqlite`, `notes.sqlite`, `lxx.sqlite`, `ancient.sqlite`,
`graph.sqlite`, and, from the data version that adds them,
`translations.sqlite` and `scrolls.sqlite`) are published at
https://bezalel.genericjam.com/packs/manifest.json, zstd-compressed with
their checksums; how they're built: bezalel_mob's
[data/README.md](https://github.com/GenericJam/bezalel_mob/blob/master/data/README.md)
for the first five, this repository's [data/README.md](data/README.md) for
the last two. The scrolls pack's text is ETCBC/dss (Martin G. Abegg Jr.,
James E. Bowley and Edward M. Cook), CC BY-NC 4.0: non-commercial use, with
that credit shown; no English translation is included.

## Development

```bash
mix setup     # deps and the git hooks
mix test      # against the small fixture packs in test/fixtures/packs
```

Elixir 1.20 on OTP 29 (`.tool-versions`). Contributors and coding agents:
start with [AGENTS.md](AGENTS.md).
