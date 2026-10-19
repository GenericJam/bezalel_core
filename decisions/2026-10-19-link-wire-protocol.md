# Link wire protocol in bezalel_core

Date: 2026-10-19. Status: accepted (P0 of "the phone is the account").

## Decision

The phone ↔ website link's pure parts live here, shared by both apps:
`Bezalel.Link.Handshake` (hello/auth, Ed25519 signatures over
length-prefixed transcripts, X25519 + HKDF-SHA256 keys per direction,
AES-256-GCM sealing with explicit per-direction counters),
`Bezalel.Link.Wire` (JSON frames `{op, id | re}`, 256 KiB base64url chunks,
a window of 4, 1 MiB frames; an assembly holds at most 256 MiB in 4096
chunks unless the caller says otherwise) and `Bezalel.Link.Pairing` (the
QR code, the claim HMAC, the account id and fingerprint). Sockets,
storage and screens stay in the apps.

## Why

One tested implementation on both ends; frames are sealed on top of TLS
because Cloudflare terminates TLS at its edge. The auth signature also
binds the server key and the device key (beyond the design's list), so a
device signature is valid for one server key and one connection only,
and the phone's `app` and `platform` labels, so the TLS terminator can't
relabel a session in the user's list of them. Since the account is the
device key, the server refuses Ed25519's 8 small-order keys and
non-canonical encodings: OpenSSL verifies a signature anyone can forge
under them (the identity key takes `identity <> <<0::256>>` over any
message), so such an account would have no owner. Known-answer tests
were computed with an independent implementation (Python
`cryptography`).

Decoding and checking never raise on what a peer sends: `Wire.decode/1`,
`Pairing.parse_qr/1`, `server_key?/2` and `valid_claim?/4` answer
anything that isn't a binary with their error or false. An assembly is
bounded by default (bytes, and chunks so empty ones count) because any
phone can make an account and stream chunks that never end.

Also here: `Transcript.merge/3` (conflict merge as branch copies) and
draw_image's `:credential`/`:signed_in` hooks taking `(provider, ctx)`
(one-argument hooks still work, so the apps needed no change). The merge
takes the common entries themselves, not only their ids: Delete and Undo
copy entries with new ids, so a website that deleted or undid while apart
holds copies of common entries, which are recognised by what a copy keeps
(everything but `id`, `parentId` and `timestamp`). Only in a branch that
moved off the common leaf (no other holds copies), and only as its leading
run; and against the phone's own entries only for messages (which carry
their own time): a model switch or a notice can equal an unrelated
earlier one, so a website switching back to an earlier model keeps it.
The website's Delete or Undo wins over the common part (when both moved,
the phone's is lost: the originals stay on an inactive branch); each
side's new turns follow in the order they began, by message time, which
copies keep.
