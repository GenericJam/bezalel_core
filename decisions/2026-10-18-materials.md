# Materials: files to and from the agent, read-aloud and dictation

2026-10-18. Status: accepted (Kevin's decisions below; the contracts are
core's, agreed with rho's attachments by reference).

## Context

Bezalel answered text with text, plus the pictures a tool or a model made
and photos the phone attached inline (base64 in the rho session). Kevin
wants the agent to take and give files of every kind, to read replies
aloud and to take dictation, in the phone app (bezalel_mob) and the
website (bezalel_ca) alike. A library of photos stored inline would bloat
every session, and no model Bezalel runs takes everything: so the files
need a home of their own, a rule for what each model gets, and the same
answers in both apps (the house rule: shared code in bezalel_core).

## Kevin's decisions

- The category is called **Materials**: what Bezalel brought to the bench
  and what came off it ("gold, silver, bronze, cutting stones, carving
  wood", Ex 31:4–5). Workshop stays for now.
- A material is anything sent to or received from the agent: images
  (photos, screenshots), audio, video, documents (PDF and other files),
  and their derivatives (transcripts, audio tracks, stills, generated
  images).
- A **+ button** beside the question box: attach an existing file (photo
  library, files) or capture one (photo, video, audio).
- **Read replies aloud** (TTS) and **dictation** (STT).
- **Audio** a model can't take is transcribed first; the model gets the
  transcript, Materials keeps the audio. Phone: the platform recogniser
  for live dictation (mob_speech), Whisper on the phone (mob_whisper) for
  recordings and as fallback. Web: Whisper on the server.
- **Video**: no model watches it. The user is told the limits *before*
  upload, in these words (`Bezalel.Materials.video_notice/0`):
  "Bezalel doesn't watch videos. It reads what's said (a transcript) and
  the stills you choose. On-screen text, gestures, music and anything not
  spoken or in a still won't reach it." The audio track is transcribed;
  the user picks stills, which are image materials. The original video and
  its derivatives are kept. Editing, enhancing or generating video is out
  of scope.
- **Generated images** may be billed to the user's API key: OpenAI
  gpt-image through `ReqLLM.generate_image`, edits from reference images;
  Gemini later.
- **Website voice**: the browser's `speechSynthesis` (free).
- Order: (1) the foundation, the + menu for photos, camera and files,
  images and PDFs to the model, the Materials tab/page, read-aloud,
  dictation; (2) audio attachments, `draw_image`; (3) video.

What a model takes (`Rho.Models.inputs/1`):

| kind | Claude | GPT | Gemini |
|---|---|---|---|
| image | yes | yes | yes |
| PDF | yes | partly | yes |
| audio | no | special audio models only | yes |
| video | no | no | yes |

## Decisions (core)

### Where each piece lives

- **rho**: attachments by reference (an attachment carries the host's
  `ref` and its metadata; the session stores no bytes; rho fetches them
  through the host's `:resolve_attachment` hook when it builds a request;
  inline image parts of older sessions still read). Unreleased: core pins
  rho by GitHub commit until a release, which needs Kevin's OK.
- **bezalel_core**: `Bezalel.Materials` (record, kinds, media types,
  content addressing, file layout, derivatives, the routing rule, the
  resolver, the video notice, the store behaviour), `Bezalel.Speech`, the
  `draw_image` tool, and the messages' materials
  (`Bezalel.Library.Message`, `Bezalel.Agent.Reply`).
- **The apps**: the store (the phone's Ecto table and files in app
  support, backed up, since they are the user's own; the website's per-user
  table and files under its data dir), capture and pickers, recording,
  transcription, the voice, the Materials tab/page, drawing materials in
  messages.
- **mob_media** (a new Mob plugin): the phone's media helpers (duration
  and size, an audio track as PCM for Whisper, a frame as JPEG).

### The record

`Bezalel.Materials.Material`: `id` (SHA-256 of the bytes, lowercase hex:
the same bytes are one material), `kind` (`:image | :audio | :video |
:document | :transcript`), `mime`, `name`, `size`, `source` (`:sent |
:received | :derived`), `derivation` (nil, `:transcript`, `:audio_track`,
`:still`, `:generated`), `derived_from` (ids), `meta` (`:duration_ms`,
`:width`, `:height`, `:pages`, `:at_ms`, `:prompt`, `:model`),
`inserted_at`. `to_map/1` / `from_map/1` are its JSON form.

- A still and a generated picture are **images** with a derivation, not
  kinds of their own: everything that shows, sends or references a picture
  treats them as pictures; `derivation` says where they came from.
- `:transcript` is the kind of every text Bezalel derives: what's said in
  an audio or video, and a document's extracted text (derivation
  `:transcript` both). One derivation, one lookup.
- A drawing is `source: :received` (the agent gave it), derivation
  `:generated`, `derived_from` its reference pictures (`[]` from words
  alone). Transcripts, audio tracks and stills are `:derived`.
- The file layout under a host directory is `ab/<id>.<ext>`
  (`relative_path/1`; `write_file/3` writes through a temporary file and
  checks the bytes). The extension is there because players want one.

### The host's store

`config :bezalel_core, :materials, MyApp.MaterialStore`, a module with
the `Bezalel.Materials.Store` behaviour (a behaviour rather than an MFA
like `:preferences`, since it has several operations):

```elixir
@callback put(material :: Material.t(), bytes :: binary(), ctx()) ::
            {:ok, Material.t()} | {:error, term()}
@callback fetch(id :: String.t(), ctx()) :: {:ok, Material.t()} | :error
@callback read(material :: Material.t(), ctx()) :: {:ok, binary()} | {:error, term()}
@callback derivatives(id :: String.t(), ctx()) :: [Material.t()]
@callback for_model(material :: Material.t(), ctx()) ::
            {:ok, {String.t(), binary()}} | {:error, term()}
@optional_callbacks for_model: 2
```

`ctx` always has `:session_id` (the rho session: a tool's ctx, rho's
resolver ctx, or the host's own when it sends a question), so a host with
several users finds the owner from the conversation, and **every callback
answers only for that owner**: `fetch/2` is `:error`, `read/2` an error
and `derivatives/2` leaves out another owner's materials. The same bytes
from two users are one id kept for each. `put/3` of a material already
kept keeps `Bezalel.Materials.merge(kept, new)`: the parents of both, so
identical derivatives (the empty transcript of two silent videos, one
black still from two clips) belong to every material they came from; the
record (kind, name) is the first one's. `for_model/2` is for a host that sends models a
resized or re-encoded copy (a phone photo is larger than providers take);
without it they get `read/2`'s bytes. `Bezalel.Materials.store/0` checks
the configured module loads and has the callbacks (`{:error,
{:bad_store, m}}` otherwise), so a tool fails before it spends anything.

### What goes to the model

`Bezalel.Materials.route/3` (pure) and `attachments/4` (through the store,
which fetches each material again by id with the ctx, so a caller can't
send another owner's material by handing over its struct):

- an **image** attaches by reference (rho resolves it; a model without
  `:image` gets rho's note). One in a format not every provider takes
  (anything but JPEG, PNG and WebP: HEIC from a phone, a GIF) goes by name
  only, unless the store converts it (`for_model/2`): otherwise every
  later request of the conversation would carry a picture the provider
  rejects;
- a **PDF** attaches by reference to a model with `:pdf`, else goes as
  its extracted text (a `:transcript` derivative) when there is one, else
  by name only;
- **audio and video** go as their newest transcript (made from them or
  from their audio track), whatever the model takes: rho sends no sound,
  and a transcript is kept anyway for search and the chat. Stills go as
  the image materials they are, when the user sends them. One with no
  transcript makes `attachments/4` answer `{:missing, materials}`, and the
  host transcribes before sending;
- a **text file** goes as its text; any other document by name only.

Texts are cut at 100 000 characters (`:text_max`), saying how much was
left out; a text that isn't valid UTF-8 loses only its invalid bytes (to
U+FFFD). An attachment is rho's shape:
`%{kind: :image | :pdf | :text | :file, ref: id, name, mime, about}`
(`text:` for `:text`, `pages:` for a PDF that knows them).

### rho's resolver

`config :rho, :resolve_attachment, {Bezalel.Materials, :resolve, []}`:
rho calls `resolve(attachment, %{session_id: id})` with the stored
string-keyed attachment (`"ref"`, `"kind"`, `"mimeType"`, `"name"`) for
an image the model takes or a PDF it takes, and gets `{:ok, {mime, bytes}}`
(the store's `for_model/2`, else its bytes) or `{:error, reason}`, for
which the model gets a note that the file couldn't be loaded.

### Messages

`Bezalel.Library.Message.materials` (and `Bezalel.Agent.Reply.materials`,
live) lists the materials a message sent or received by reference, each
`%{id, kind, mime, name, about, entry}` (the kind by media type: what the
chat draws), from rho's `attachments` on user
messages and tool results. `images` is unchanged (pictures stored inline:
older sessions, model-made pictures, tools that return bytes), so a
session from before materials reads as it did. A reply that is only a
drawing still shows.

### draw_image

`Bezalel.Study.Tools.DrawImage` (`draw_image`): `prompt` (required),
`references` (one material id), `size` (`square` 1024×1024, `landscape`
1536×1024, `portrait` 1024×1536). It calls `ReqLLM.generate_image/3` with
`openai:gpt-image-2` (configurable), JPEG output, the user's OpenAI API
key (`Rho.Auth.credential(:openai)`), and with a reference, its bytes as
`source_image` (the edits endpoint). It keeps the drawing through the
store and returns it to rho by reference (`{:ok, {:images, [%{ref, mime,
name}], text}}`), the text naming its ref so the model can draw from it
again.

- **One reference**, not several: req_llm 1.28's edits form carries one
  image. More is a clear error, as is a reference that isn't JPEG, PNG or
  WebP after the store's `for_model/2` (what the edits endpoint takes).
- It checks the store, the arguments, the reference and the key **before**
  it calls the API, so a failure costs nothing. Without a key: "Drawing a
  picture needs an OpenAI API key, and none is set. Tell the user to add
  one in Settings (OpenAI, API key); drawings are billed to that key." A
  refusal reaches the model in OpenAI's words.
- **Not a study tool and not a source**: it reads no pack and has nothing
  to credit or switch off, so it is not in `Tools.all/0` (nor in
  `Bezalel.Study.Sources`) but in `Tools.materials/0`, which a host offers
  once it has a store. The model's guidance is the tool's description, so
  the system prompt is unchanged.
- Tests replace the image call and the credential through `config
  :bezalel_core, :draw_image` (`:generate`, `:credential`); none touches
  the network.

### Read-aloud

`Bezalel.Speech.speakable/1` takes the reply's SUMMARY (the caller picks
it) and returns text for a voice: headings, list items and table rows as
sentences (a row with its column names), code blocks and breaks dropped,
emphasis, quote marks, images, footnote marks, HTML and URLs gone, links
as their text; Hebrew and Greek replaced by the transliteration the model
gave in parentheses right after them, else dropped (an English voice reads
neither); a Strong's number in parentheses dropped; verse references said
aloud through `Bezalel.Study.Reference` ("Ex 31:3" is "Exodus 31 verse 3",
"1 Cor 13:4-7" "First Corinthians 13 verses 4 to 7"). Chapter-only
references ("Dan 3") are left alone: too many book abbreviations are also
words and names.

## What the apps implement

- A `Bezalel.Materials.Store` and `config :bezalel_core, :materials`;
  `config :rho, :resolve_attachment, {Bezalel.Materials, :resolve, []}`
  (or their own, to resize first: `for_model/2` is the simpler way).
- rho at the same GitHub commit as core (an override while the app's own
  requirement says Hex).
- Sending: `Bezalel.Materials.attachments/4` for the question, transcribing
  what it reports missing; `video_notice/0` before a video.
- Offering `Bezalel.Study.Tools.materials/0` beside `all/0`.
- Drawing `Message.materials` (by kind) beside `images`; the Materials
  tab/page from the store.
- Read-aloud through their voice with `Bezalel.Speech.speakable/1`;
  dictation and transcription with their engines.
