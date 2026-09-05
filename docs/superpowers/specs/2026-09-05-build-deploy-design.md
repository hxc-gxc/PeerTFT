# PeerTFT — Multi-platform Build & Deploy Design

**Date:** 2026-09-05
**Status:** Approved

---

## 1. Goal

Build PeerTFT for Android, Web, Linux, macOS, and Windows via GitHub Actions. Deploy the signaling server and Flutter web app to an existing Dokploy VPS at `noredflag.fr`. Enable cross-network P2P file transfer testing between real devices.

iOS is deferred (no Apple Developer account yet).

---

## 2. Architecture

```
signal.noredflag.fr  →  Traefik (Dokploy global)  →  signaling:8080   (WSS)
peer.noredflag.fr    →  Traefik (Dokploy global)  →  web:80           (HTTPS static)
UDP 3478             →  coturn                     (raw UDP, no Traefik)
```

Three services in `docker-compose.yml`: **signaling**, **web**, **stun**. Caddy removed.
Traefik is a pre-existing global container managed by Dokploy — not added to this compose.
Services join `dokploy-network` external network via labels.

---

## 3. Docker Images

### Image names
- Signaling: `ghcr.io/hxc-gxc/peertft-signaling`
- Web: `ghcr.io/hxc-gxc/peertft-web`

Both tagged `:latest` and `:<github.sha>` on each push.

### 3a. Signaling
Existing `packages/signaling_server/Dockerfile` — no changes. Build context: repo root.

### 3b. Web (`packages/app/Dockerfile.web`)

Build context: repo root (required so `packages/shared` path dependency resolves).

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

Production values are passed as `--build-arg` in the CI `docker build` step.

---

## 4. App Config

**File:** `packages/app/lib/src/state/transfer_session.dart` (lines 90-92)

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

Note: `const String.fromEnvironment(...)` is a valid Dart compile-time constant. `Uri.parse` is called on it as a `final` field initializer — this compiles correctly. Local dev: defaults apply unchanged.

---

## 5. Infrastructure Changes

### 5a. `docker-compose.yml` — full delta

- **Remove:** `caddy` service, `caddy_data` volume, `caddy_config` volume
- **Remove:** `Caddyfile` file (delete)
- **signaling:** replace `build:` with `image: ghcr.io/hxc-gxc/peertft-signaling:latest`, replace `ports: ["8080:8080"]` with `expose: ["8080"]`, add labels + network
- **Add new `web` service** (see 5b)
- **stun:** add `--external-ip=<VPS_PUBLIC_IP>` to command (hardcode the VPS IP — more reliable than runtime curl)
- **Add** external network declaration at bottom

### 5b. Full service definitions

**signaling:**
```yaml
signaling:
  image: ghcr.io/hxc-gxc/peertft-signaling:latest
  restart: unless-stopped
  environment:
    PORT: "8080"
  expose:
    - "8080"
  networks:
    - dokploy-network
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.peertft-signaling.rule=Host(`signal.noredflag.fr`)"
    - "traefik.http.routers.peertft-signaling.entrypoints=websecure"
    - "traefik.http.routers.peertft-signaling.tls.certresolver=letsencrypt"
    - "traefik.http.services.peertft-signaling.loadbalancer.server.port=8080"
```

**web:**
```yaml
web:
  image: ghcr.io/hxc-gxc/peertft-web:latest
  restart: unless-stopped
  expose:
    - "80"
  networks:
    - dokploy-network
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.peertft-web.rule=Host(`peer.noredflag.fr`)"
    - "traefik.http.routers.peertft-web.entrypoints=websecure"
    - "traefik.http.routers.peertft-web.tls.certresolver=letsencrypt"
    - "traefik.http.services.peertft-web.loadbalancer.server.port=80"
    - "traefik.http.middlewares.peertft-https-redirect.redirectscheme.scheme=https"
    - "traefik.http.routers.peertft-web-http.rule=Host(`peer.noredflag.fr`)"
    - "traefik.http.routers.peertft-web-http.entrypoints=web"
    - "traefik.http.routers.peertft-web-http.middlewares=peertft-https-redirect"
```

**stun:**
```yaml
stun:
  image: coturn/coturn:latest
  restart: unless-stopped
  command: ["-n", "--stun-only", "--listening-port=3478", "--external-ip=<VPS_PUBLIC_IP>"]
  ports:
    - "3478:3478/udp"
```

**Networks block (bottom of file):**
```yaml
networks:
  dokploy-network:
    external: true
```

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
    docker build \
      --file packages/app/Dockerfile.web \              # web job only
      --build-arg SIGNALING_WS_URL=wss://signal.noredflag.fr/ws \  # web job only
      --build-arg SIGNALING_HTTP_URL=https://signal.noredflag.fr \  # web job only
      --build-arg STUN_URL=stun:signal.noredflag.fr:3478 \          # web job only
      -t ghcr.io/hxc-gxc/peertft-web:latest \
      -t ghcr.io/hxc-gxc/peertft-web:${{ github.sha }} \
      .
    docker push ghcr.io/hxc-gxc/peertft-web:latest
    docker push ghcr.io/hxc-gxc/peertft-web:${{ github.sha }}
```

### Linux build dependencies

```yaml
- run: |
    sudo apt-get update
    sudo apt-get install -y \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev \
      libwebkit2gtk-4.1-dev \
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

Dokploy webhook must be type **"Redeploy"** — triggers `docker compose pull && docker compose up -d`.

### Secrets required

| Secret | Purpose |
|---|---|
| `GHCR_TOKEN` | PAT with `write:packages` scope |
| `DOKPLOY_WEBHOOK_URL` | Dokploy "Redeploy" webhook URL |

---

## 7. Dokploy Setup (manual, one-time)

1. Create a "Docker Compose" project in Dokploy pointing at this repo
2. Set compose file to `docker-compose.yml`
3. Configure domains in Dokploy's domain panel: `signal.noredflag.fr` and `peer.noredflag.fr`
4. Open UDP 3478 in VPS firewall (80/443 already open for Traefik)
5. **GHCR access:** Go to GitHub → Packages → `peertft-signaling` and `peertft-web` → Change visibility → **Public**. No Dokploy registry config needed.
6. Copy the **"Redeploy" webhook URL** from Dokploy → add as GitHub secret `DOKPLOY_WEBHOOK_URL`
7. Create GitHub PAT with `write:packages` → add as GitHub secret `GHCR_TOKEN`
8. Note VPS public IP and replace `<VPS_PUBLIC_IP>` placeholder in `docker-compose.yml` stun command

---

## 8. Testing

1. Push to `main` → confirm all CI jobs green, artifacts downloadable, both images appear in GHCR
2. Dokploy webhook fires → containers restart with new images
3. Verify `wss://signal.noredflag.fr/ws` returns 101 Switching Protocols
4. Open `https://peer.noredflag.fr` on two devices on **different networks** (phone on 4G + laptop on WiFi)
5. Device A picks a file, shares room code; Device B enters the code
6. WebRTC handshake via signaling → DataChannel opens → transfer completes
7. Confirm P2P in logs/DevTools (no relay — TURN intentionally absent)

**Expected failure mode:** Symmetric NAT causes ICE failure with explicit error in UI. STUN-only works for ~85% of real-world NAT configurations.

---

## 9. Out of Scope

- iOS (deferred — needs Apple Developer account)
- Google Play signing (deferred — APK is debug for now)
- TURN relay (intentionally omitted — server never sees file bytes)
- Staging environment
