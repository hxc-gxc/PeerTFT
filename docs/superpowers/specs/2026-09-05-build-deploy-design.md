# PeerTFT — Multi-platform Build & Deploy Design

**Date:** 2026-09-05
**Status:** Approved

---

## 1. Goal

Build PeerTFT for Android, Web, Linux, macOS, and Windows via GitHub Actions. Deploy the signaling server and Flutter web app to the existing Dokploy VPS at `noredflag.fr` as an isolated new project. Enable cross-network P2P file transfer testing between real devices.

iOS is deferred (no Apple Developer account yet).

---

## 2. Architecture

```
signal.noredflag.fr  →  Traefik (Dokploy-managed)  →  signaling:8080   (WSS)
peer.noredflag.fr    →  Traefik (Dokploy-managed)  →  web:80           (HTTPS static)
UDP 3478             →  coturn                      (raw UDP, no Traefik)
```

Three services in `docker-compose.yml`: **signaling**, **web**, **stun**.
Caddy is removed — Traefik routing is configured via the **Dokploy UI domain panel**, not via
compose labels. This matches how all existing apps on this VPS (`noredflag.fr`, `/app`,
`/app-preview`) are already managed — no risk to those deployments.

---

## 3. Docker Images

### Image names (GHCR)
- `ghcr.io/hxc-gxc/peertft-signaling` — tagged `:latest` and `:<github.sha>`
- `ghcr.io/hxc-gxc/peertft-web` — tagged `:latest` and `:<github.sha>`

Both pushed by CI. Dokploy pulls on webhook trigger. GHCR packages set to **public**.

### 3a. Signaling (`packages/signaling_server/Dockerfile`)
No changes. Build context: repo root.
- Stage 1: `dart:stable` — AOT compile `bin/server.dart`
- Stage 2: `debian:bookworm-slim` — runs binary, exposes 8080

### 3b. Web (`packages/app/Dockerfile.web`) — new file
Build context: repo root (required for `packages/shared` path dependency).

```dockerfile
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.yaml ./pubspec.yaml
COPY packages/shared ./packages/shared
COPY packages/app ./packages/app

# Strip signaling_server from workspace so dart pub get succeeds without it
RUN sed -i '/- packages\/signaling_server/d' pubspec.yaml

WORKDIR /app/packages/app

ARG SIGNALING_WS_URL=ws://localhost:8080/ws
ARG SIGNALING_HTTP_URL=http://localhost:8080
ARG STUN_URL=stun:localhost:3478

RUN flutter pub get
RUN flutter build web \
    --dart-define=SIGNALING_WS_URL=$SIGNALING_WS_URL \
    --dart-define=SIGNALING_HTTP_URL=$SIGNALING_HTTP_URL \
    --dart-define=STUN_URL=$STUN_URL

FROM nginx:alpine
COPY --from=build /app/packages/app/build/web /usr/share/nginx/html
EXPOSE 80
```

Production values passed as `--build-arg` in the CI `docker build` step.

---

## 4. App Config

**File:** `packages/app/lib/src/state/transfer_session.dart` (lines 90–92)

```dart
// Before:
static final _signalingWsUri = Uri.parse('ws://localhost:8080/ws');
static final _signalingHttpUri = Uri.parse('http://localhost:8080');
static const _stunUri = 'stun:localhost:3478';

// After:
static final _signalingWsUri = Uri.parse(
  const String.fromEnvironment('SIGNALING_WS_URL', defaultValue: 'ws://localhost:8080/ws'),
);
static final _signalingHttpUri = Uri.parse(
  const String.fromEnvironment('SIGNALING_HTTP_URL', defaultValue: 'http://localhost:8080'),
);
static const _stunUri =
    String.fromEnvironment('STUN_URL', defaultValue: 'stun:localhost:3478');
```

`const String.fromEnvironment(...)` is a Dart compile-time constant; `Uri.parse` wraps it
as a `final` field — valid, compiles correctly. Local dev: defaults apply, no flags needed.

---

## 5. `docker-compose.yml` Changes

**Remove:** `caddy` service, `caddy_data` volume, `caddy_config` volume, `Caddyfile` file.

**Final compose** (Traefik routing handled by Dokploy UI — no labels needed):

```yaml
services:
  signaling:
    image: ghcr.io/hxc-gxc/peertft-signaling:latest
    restart: unless-stopped
    environment:
      PORT: "8080"
    expose:
      - "8080"

  web:
    image: ghcr.io/hxc-gxc/peertft-web:latest
    restart: unless-stopped
    expose:
      - "80"

  stun:
    image: coturn/coturn:latest
    restart: unless-stopped
    command: ["-n", "--stun-only", "--listening-port=3478", "--external-ip=<VPS_PUBLIC_IP>"]
    ports:
      - "3478:3478/udp"
```

Replace `<VPS_PUBLIC_IP>` with the VPS public IP before committing (hardcoded is more
reliable than runtime `curl ifconfig.me` in a container entrypoint).

---

## 6. GitHub Actions Workflow

Replaces `.github/workflows/ci.yml`. Triggers: `push` to `main`, `pull_request`.

### Jobs

| Job | Runner | Details |
|---|---|---|
| `lint` | `ubuntu-latest` | checkout, flutter-action@v2, melos bootstrap, format + analyze + test |
| `build-signaling-image` | `ubuntu-latest` | checkout, docker login GHCR, build + push signaling image |
| `build-web-image` | `ubuntu-latest` | checkout, docker login GHCR, build with `--build-arg` for 3 URLs, push web image |
| `build-android` | `ubuntu-latest` | checkout, setup-java@v4 (temurin 17), flutter-action@v2, melos bootstrap, `flutter build apk --debug`, upload-artifact |
| `build-linux` | `ubuntu-latest` | checkout, apt-get GTK+webkit deps, flutter-action@v2, melos bootstrap, `flutter build linux`, upload-artifact |
| `build-macos` | `macos-latest` | checkout, flutter-action@v2, melos bootstrap, `flutter build macos`, upload-artifact |
| `build-windows` | `windows-latest` | checkout, flutter-action@v2, melos bootstrap, `flutter build windows`, upload-artifact |
| `deploy` | `ubuntu-latest` | `needs: [lint, build-signaling-image, build-web-image]`, `if: main` only |

### Image push steps (both image jobs)

```yaml
- uses: actions/checkout@v4.2.2
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GHCR_TOKEN }}
- name: Build and push
  run: |
    IMAGE=ghcr.io/hxc-gxc/peertft-web   # (peertft-signaling for signaling job)
    docker build \
      --file packages/app/Dockerfile.web \                          # web job only
      --build-arg SIGNALING_WS_URL=wss://signal.noredflag.fr/ws \  # web job only
      --build-arg SIGNALING_HTTP_URL=https://signal.noredflag.fr \ # web job only
      --build-arg STUN_URL=stun:signal.noredflag.fr:3478 \         # web job only
      -t $IMAGE:latest \
      -t $IMAGE:${{ github.sha }} \
      .
    docker push $IMAGE:latest
    docker push $IMAGE:${{ github.sha }}
```

### Linux build dependencies

```yaml
- run: |
    sudo apt-get update
    sudo apt-get install -y \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev libwebkit2gtk-4.1-dev \
      liblzma-dev libstdc++-12-dev
```

### Deploy job

```yaml
deploy:
  needs: [lint, build-signaling-image, build-web-image]
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - run: curl -X POST "${{ secrets.DOKPLOY_WEBHOOK_URL }}"
```

Dokploy webhook type: **"Redeploy"** — triggers `docker compose pull && docker compose up -d`.

### Secrets required

| Secret | Purpose |
|---|---|
| `GHCR_TOKEN` | PAT with `write:packages` scope |
| `DOKPLOY_WEBHOOK_URL` | Dokploy "Redeploy" webhook URL |

---

## 7. Dokploy Setup (manual, one-time)

1. Create a new **"Docker Compose"** project in Dokploy pointing at the PeerTFT repo — completely separate from existing projects, no shared config
2. Set compose file path to `docker-compose.yml`
3. In Dokploy's **domain panel**, configure:
   - `signal.noredflag.fr` → service `signaling`, port `8080`, enable HTTPS
   - `peer.noredflag.fr` → service `web`, port `80`, enable HTTPS
4. Open UDP 3478 in VPS firewall
5. Set both GHCR packages to **public** (GitHub → Packages → Change visibility)
6. Copy the **"Redeploy" webhook URL** from Dokploy → add as GitHub secret `DOKPLOY_WEBHOOK_URL`
7. Create GitHub PAT (`write:packages`) → add as GitHub secret `GHCR_TOKEN`
8. Replace `<VPS_PUBLIC_IP>` in `docker-compose.yml` stun command with the actual VPS IP

---

## 8. Testing

1. Push to `main` → confirm all CI jobs green, artifacts downloadable, both images in GHCR
2. Dokploy webhook fires → `docker compose pull` + `up -d` on VPS
3. Verify `wss://signal.noredflag.fr/ws` accepts WebSocket connections (101)
4. Open `https://peer.noredflag.fr` on two devices on **different networks** (e.g. phone on 4G + laptop on WiFi)
5. Device A picks a file, shares room code; Device B enters the code
6. WebRTC handshake via signaling → DataChannel opens → transfer completes
7. Confirm P2P in DevTools (no relay — TURN intentionally absent)

**Expected failure mode:** Symmetric NAT → ICE failure with explicit error in UI. STUN-only works for ~85% of real-world NAT types.

---

## 9. Out of Scope

- iOS (deferred — no Apple Developer account)
- Google Play signing (deferred — APK is debug for now)
- TURN relay (intentionally omitted — server never sees file bytes)
- Staging environment
