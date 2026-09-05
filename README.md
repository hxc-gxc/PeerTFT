# PeerTFT

A Flutter P2P file transfer app: two users exchange a file directly,
end-to-end encrypted, with **no server ever storing or relaying the file
itself**. Full rationale and design in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Status

This repository currently holds the **throwaway prototype** described in
`ARCHITECTURE.md` section 13: enough to validate room matching and a raw
WebRTC handshake between two Flutter clients over a self-hosted signaling
server + STUN, with ICE-outcome instrumentation. It does **not** yet include
file chunking, the application-layer encryption (X25519+HKDF / SPAKE2), or
the full UI from section 9 -- those come next, once the handshake and NAT
traversal numbers from this prototype are validated.

> **Unverified code.** This was written in a sandbox without the Dart or
> Flutter SDKs installed, so nothing here has been run through
> `dart pub get`, `dart analyze`, `dart test`, or `flutter run`. Treat it as
> a first pass: run the steps below locally and fix whatever the toolchain
> flags before relying on it.

## Layout

```
packages/
  shared/            Pure Dart. Signaling message types, WebRTC offer/
                      answer/ICE payload types, room-code generator.
  signaling_server/   Pure Dart. Stateless WebSocket room-matching relay
                      (see lib/src/room_manager.dart) + a minimal
                      POST /metrics endpoint for ICE-outcome instrumentation.
  app/                Flutter client. Currently just the handshake
                      prototype (lib/src/ui/handshake_test_page.dart).
docker-compose.yml    signaling + coturn (STUN only, no TURN) + Caddy (TLS).
Caddyfile
```

## Getting started

Requires the [Dart SDK](https://dart.dev/get-dart) (or Flutter, which
bundles it), [Melos](https://melos.invertase.dev/), and Docker for the infra
pieces.

```bash
dart pub global activate melos
melos bootstrap   # links the path deps across packages/*
melos run analyze
melos run test
```

### Backfilling the Flutter platform folders

`packages/app` ships only `pubspec.yaml` and `lib/`: the `android/`, `ios/`,
`web/`, `macos/`, `linux/` and `windows/` folders that `flutter create`
normally generates are not present (no Flutter SDK was available to
generate them here). Add the platforms you need with:

```bash
cd packages/app
flutter create . --platforms=android,ios,web,macos,linux,windows
```

This only adds the missing platform scaffolding; it does not touch the
existing `lib/` or `pubspec.yaml`.

### Running the signaling server + STUN locally

```bash
docker compose up --build signaling stun
```

The server listens on `:8080` (`/ws` for signaling, `POST /metrics`,
`GET /healthz`); coturn listens on UDP `:3478`. `caddy` is only needed for a
real TLS deployment behind a domain name -- edit `Caddyfile` first.

### Running the prototype client

`packages/app/lib/main.dart` currently points at `localhost:8080` /
`stun:localhost:3478`. With the signaling server running, launch two
instances of the app (e.g. two desktop windows, or a browser tab + a
desktop build) and, on one, tap **Create room** -- copy the generated code
into the other instance's text field and tap **Join room**. If the ICE
handshake succeeds, both sides log a `hello` exchange.

## Non-negotiable design decisions

See `ARCHITECTURE.md` section 12 for the full list; the two easiest to
break by accident when extending this code:

- **No TURN, no relay fallback.** `docker-compose.yml` only runs coturn in
  `--stun-only` mode. A failed ICE negotiation must surface as an explicit
  error to the user, never a silent fallback.
- **The signaling server never inspects WebRTC payloads.** It only reads
  the outer `RelayMessage.targetPeerId` to route; `payload` is opaque JSON
  produced and consumed entirely by the clients.

## Known gaps before this goes further

- No application-layer E2E encryption yet (needs a dedicated crypto review
  before it's implemented for real -- see `ARCHITECTURE.md` section 4).
- No file chunking / streaming-to-disk (`ARCHITECTURE.md` sections 5-6).
- `packages/shared/lib/src/codes/wordlist_fr.dart` has 312 words, not the
  2000-4000 the architecture doc targets; codes compensate by drawing 4
  words instead of 3 (~9.5 billion combinations). Expand the wordlist
  before shipping.
- No CI configured yet.
