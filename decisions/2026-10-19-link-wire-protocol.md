# Link wire protocol in bezalel_core

Date: 2026-10-19. Status: accepted (P0 of "the phone is the account").

## Decision

The phone ↔ website link's pure parts live here, shared by both apps:
`Bezalel.Link.Handshake` (hello/auth, Ed25519 signatures over
length-prefixed transcripts, X25519 + HKDF-SHA256 keys per direction,
AES-256-GCM sealing with explicit per-direction counters),
`Bezalel.Link.Wire` (JSON frames `{op, id | re}`, 256 KiB base64url chunks,
a window of 4, 1 MiB frames) and `Bezalel.Link.Pairing` (the QR code, the
claim HMAC, the account id and fingerprint). Sockets, storage and screens
stay in the apps.

## Why

One tested implementation on both ends; frames are sealed on top of TLS
because Cloudflare terminates TLS at its edge. The auth signature also
binds the server key and the device key (beyond the design's list), so a
device signature is valid for one server key and one connection only.
Known-answer tests were computed with an independent implementation
(Python `cryptography`).

Also here: `Transcript.merge/3` (conflict merge as branch copies) and
draw_image's `:credential`/`:signed_in` hooks taking `(provider, ctx)`
(one-argument hooks still work, so the apps needed no change).
