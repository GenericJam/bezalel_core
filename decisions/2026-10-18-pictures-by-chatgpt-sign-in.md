# Pictures by the ChatGPT sign-in

2026-10-18. Status: accepted (Kevin's ask: draw with the ChatGPT sign-in
instead of an API key; the precedence below is this change's decision).

## Context

`draw_image` (bezalel_core) drew only on an API key: OpenAI's gpt-image
on an OpenAI key, or a Gemini image model on a Gemini key. Kevin's phone
is signed in to ChatGPT (Plus, the Codex OAuth sign-in rho already has for
answers) and has no OpenAI key, so it couldn't draw; asking "Claude, have
ChatGPT draw the ark" went nowhere (`ask_model` answers in words only).

Codex draws on that sign-in: `POST
chatgpt.com/backend-api/codex/responses` with the hosted
`image_generation` tool. A text model drives the tool; the ChatGPT
account accepts only the models Codex lists for it (`GET
/backend-api/codex/models?client_version=…`: on 2026-10-18 gpt-5.6-sol,
-terra, -luna, gpt-6-astra and more with a newer `client_version`);
gpt-5.5 and gpt-image-2 are refused with a 400. req_llm (1.26–1.28) can't
carry it: its `openai_codex` provider drops the `image_generation_call`
item, and for the gpt-5.6 models its "responses lite" contract strips
hosted tools from the request.

## Decision

- **rho 0.4 `Rho.Images.generate/2`**: a focused Req call to the Codex
  endpoint on `Rho.Auth`'s `:openai_codex` credential, driven by
  gpt-5.6-luna (the fastest that drew in testing; on a refused model it
  retries once with the first one Codex lists, Codex's own default). The
  stream is parsed as it arrives (bounded); the whole call, sign-in
  refresh included, is bounded by `:timeout`. Usage is recorded like a
  model call (`Rho.Usage`: tokens, the x-codex windows, a 429's reset, a
  dropped connection); errors are `Rho.LLM.error/0`s.
- **bezalel_core**: `DrawImage.models/0` lists ChatGPT first,
  `openai_codex:gpt-image`, "ChatGPT (your sign-in)", provider
  `:openai_codex`. Who draws (`DrawImage.model/2`): the call's `model`
  argument (the lead fills it when the user names a model: "have ChatGPT
  draw it"), else the user's Pictures by choice, else (none chosen, the
  new default: `image_model` nil) the first model whose provider is
  signed in (ChatGPT, then an OpenAI key, then Gemini), else gpt-image,
  whose missing key the tool reports. An explicit choice is never
  overridden by what's signed in. The prompt's other-models rule sends
  "have X draw" to `draw_image`, not `ask_model`. A ChatGPT drawing gets
  150 s (`Rho.Images` `:timeout`) inside the tool's 240 s, so a sign-in
  refresh before it still fits and rho's own timeout is what the user hears.
- **Apps**: Pictures by marks `DrawImage.model/2`'s model, so with none
  chosen it shows the one that will draw.

## Consequences

- A ChatGPT drawing counts against the user's ChatGPT plan (its 5-hour and
  weekly Codex windows), not a per-picture bill; the usage screens show it
  under `openai_codex:gpt-5.6-luna`.
- The phone stored the whole preferences struct, so a phone that saved
  any setting before this change has `image_model: "openai:gpt-image-2"`
  stored: that counts as a choice. Such a user picks ChatGPT under
  Pictures by once, or names it in the request.
- The website has no ChatGPT sign-in (the server signs in once, for every
  user, and Kevin hasn't): Pictures by lists ChatGPT with "Needs a ChatGPT
  sign-in", and a request for it gets the sign-in message.
- The Codex endpoint is undocumented; if it changes (the tool, the models
  list, the 400 wording rho matches for a refused model), `Rho.Images`
  is the one place to fix.
