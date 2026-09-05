# Build & Deploy Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Multi-platform CI builds (Android, Web, Linux, macOS, Windows) + deploy signaling server and Flutter web app to Dokploy VPS via GHCR images.

**Architecture:** GitHub Actions builds Docker images (signaling + web) and pushes to GHCR; a Dokploy "Redeploy" webhook pulls them on push to main. Native platform builds (Android, Linux, macOS, Windows) are uploaded as CI artifacts. Traefik routing is managed via the Dokploy UI — no labels in compose.

**Tech Stack:** Flutter 3.44.6, Dart, Docker, GitHub Actions, GHCR, Dokploy, coturn, nginx, melos 8.6.0

---

## Chunk 1: App config + infrastructure

### Task 1: Replace hardcoded URLs in transfer_session.dart

**Files:**
- Modify: `packages/app/lib/src/state/transfer_session.dart` (lines 90–92)

- [ ] **Step 1: Edit the three static URL fields**

  Open `packages/app/lib/src/state/transfer_session.dart` and replace lines 90–92:

  ```dart
  // Replace these three lines:
  static final _signalingWsUri = Uri.parse('ws://localhost:8080/ws');
  static final _signalingHttpUri = Uri.parse('http://localhost:8080');
  static const _stunUri = 'stun:localhost:3478';

  // With these:
  static final _signalingWsUri = Uri.parse(
    const String.fromEnvironment('SIGNALING_WS_URL', defaultValue: 'ws://localhost:8080/ws'),
  );
  static final _signalingHttpUri = Uri.parse(
    const String.fromEnvironment('SIGNALING_HTTP_URL', defaultValue: 'http://localhost:8080'),
  );
  static const _stunUri =
      String.fromEnvironment('STUN_URL', defaultValue: 'stun:localhost:3478');
  ```

  `const String.fromEnvironment(...)` is a Dart compile-time constant. Wrapping it in `Uri.parse` as a `final` field initializer is valid Dart — no compile error.

- [ ] **Step 2: Verify analysis passes**

  ```bash
  dart pub global activate melos 8.6.0
  melos bootstrap
  melos run analyze
  ```

  Expected: no errors or warnings.

- [ ] **Step 3: Verify tests still pass**

  ```bash
  melos run test
  melos run test:flutter
  ```

  Expected: all tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add packages/app/lib/src/state/transfer_session.dart
  git commit -m "feat: inject signaling and STUN URLs via dart-define"
  ```

---

### Task 2: Create web Dockerfile

**Files:**
- Create: `packages/app/Dockerfile.web`

Context: the Docker build runs from the **repo root** as context. The root `pubspec.yaml` declares a Dart workspace with three members: `packages/app`, `packages/shared`, `packages/signaling_server`. Because `packages/signaling_server` isn't copied into the image, the `sed` strips that line from the workspace list so `dart pub get` / `flutter pub get` succeeds without it. The signaling `Dockerfile` does the same in reverse (strips `packages/app`).

- [ ] **Step 1: Create the file**

  ```dockerfile
  # packages/app/Dockerfile.web
  # Build context must be the repo root so packages/shared path-dep resolves.
  FROM ghcr.io/cirruslabs/flutter:stable AS build
  WORKDIR /app
  COPY pubspec.yaml ./pubspec.yaml
  COPY packages/shared ./packages/shared
  COPY packages/app ./packages/app

  # Strip packages/signaling_server from the workspace declaration so
  # flutter pub get does not error on the missing package (not copied above).
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

  Note: the Dockerfile uses `ghcr.io/cirruslabs/flutter:stable` (tracks latest stable Flutter). This may differ from the `3.44.6` pinned in the CI lint/native jobs — that's acceptable for the web image. If exact reproducibility is needed later, pin to a specific cirruslabs tag.

- [ ] **Step 2: Verify the build (if Docker is available locally)**

  Run from the **repo root** — build context must be `.`:

  ```bash
  docker build -f packages/app/Dockerfile.web .
  ```

  Expected: build completes, final stage is nginx. Flutter compile takes ~3–5 min on first run.

- [ ] **Step 3: Commit**

  ```bash
  git add packages/app/Dockerfile.web
  git commit -m "feat: add web Dockerfile (Flutter build + nginx)"
  ```

---

### Task 3: Overhaul docker-compose.yml and delete Caddyfile

**Files:**
- Modify: `docker-compose.yml`
- Delete: `Caddyfile`

Current compose: `signaling` (build: + ports: 8080:8080), `stun`, `caddy` + two caddy volumes. Replacing with: `signaling` (GHCR image, expose only), `web` (new, GHCR, expose 80), `stun` (hardcoded external IP).

- [ ] **Step 1: Get the VPS public IP**

  SSH into the VPS:

  ```bash
  curl -s ifconfig.me
  ```

  Note the returned IP (e.g. `1.2.3.4`).

- [ ] **Step 2: Replace docker-compose.yml**

  Replace the entire file. Substitute `<VPS_PUBLIC_IP>` with the IP from Step 1:

  ```yaml
  # Single-VPS deployment: zero GAFAM services, no file storage anywhere.
  #
  # - signaling: stateless WebSocket room-matching relay
  # - web:       Flutter web app served by nginx
  # - stun:      self-hosted STUN only (coturn --stun-only) for NAT traversal
  #
  # Traefik routing (TLS, domains) is managed via the Dokploy UI — no labels here.
  # There is deliberately no TURN service: a TURN relay would carry file bytes
  # across this VPS, contradicting the "no server ever sees file content" principle.
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

- [ ] **Step 3: Validate the compose file**

  ```bash
  docker compose config
  ```

  Expected: YAML printed without errors, no warnings.

- [ ] **Step 4: Delete Caddyfile**

  ```bash
  git rm Caddyfile
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add docker-compose.yml
  git commit -m "feat: replace caddy with GHCR images + web service, fix stun external-ip"
  ```

---

## Chunk 2: GitHub Actions workflow

### Task 4: Rewrite ci.yml

**Files:**
- Modify: `.github/workflows/ci.yml`

**Branch protection note:** the current workflow has a job named `test`. The rewrite renames it `lint`. If you have a branch protection rule requiring the `test` job to pass, update or remove that rule in GitHub → Settings → Branches before pushing — otherwise the protection check will silently stop working.

The image build jobs (`build-signaling-image`, `build-web-image`) and `deploy` only run on push to `main`. PRs get `lint` + all native platform builds.

The `build-linux` job pins `ubuntu-22.04` (not `ubuntu-latest`) because `libwebkit2gtk-4.1-dev` requires Ubuntu 22.04+, and the default `ubuntu-latest` label may change over time.

- [ ] **Step 1: Replace .github/workflows/ci.yml entirely**

  ```yaml
  name: CI

  on:
    push:
      branches: [main]
    pull_request:

  jobs:
    lint:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4.2.2
        - uses: subosito/flutter-action@v2
          with:
            flutter-version: "3.44.6"
            channel: stable
            cache: true
        - name: Install melos
          run: dart pub global activate melos 8.6.0
        - name: Bootstrap
          run: melos bootstrap
        - name: Format
          run: melos run format
        - name: Analyze
          run: melos run analyze
        - name: Test (Dart)
          run: melos run test
        - name: Test (Flutter)
          run: melos run test:flutter

    build-signaling-image:
      runs-on: ubuntu-latest
      if: github.ref == 'refs/heads/main'
      steps:
        - uses: actions/checkout@v4.2.2
        - uses: docker/login-action@v3
          with:
            registry: ghcr.io
            username: ${{ github.actor }}
            password: ${{ secrets.GHCR_TOKEN }}
        - name: Build and push signaling image
          run: |
            docker build \
              -f packages/signaling_server/Dockerfile \
              -t ghcr.io/hxc-gxc/peertft-signaling:latest \
              -t ghcr.io/hxc-gxc/peertft-signaling:${{ github.sha }} \
              .
            docker push ghcr.io/hxc-gxc/peertft-signaling:latest
            docker push ghcr.io/hxc-gxc/peertft-signaling:${{ github.sha }}

    build-web-image:
      runs-on: ubuntu-latest
      if: github.ref == 'refs/heads/main'
      steps:
        - uses: actions/checkout@v4.2.2
        - uses: docker/login-action@v3
          with:
            registry: ghcr.io
            username: ${{ github.actor }}
            password: ${{ secrets.GHCR_TOKEN }}
        - name: Build and push web image
          run: |
            docker build \
              -f packages/app/Dockerfile.web \
              --build-arg SIGNALING_WS_URL=wss://signal.noredflag.fr/ws \
              --build-arg SIGNALING_HTTP_URL=https://signal.noredflag.fr \
              --build-arg STUN_URL=stun:signal.noredflag.fr:3478 \
              -t ghcr.io/hxc-gxc/peertft-web:latest \
              -t ghcr.io/hxc-gxc/peertft-web:${{ github.sha }} \
              .
            docker push ghcr.io/hxc-gxc/peertft-web:latest
            docker push ghcr.io/hxc-gxc/peertft-web:${{ github.sha }}

    build-android:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4.2.2
        - uses: actions/setup-java@v4
          with:
            distribution: temurin
            java-version: "17"
        - uses: subosito/flutter-action@v2
          with:
            flutter-version: "3.44.6"
            channel: stable
            cache: true
        - name: Install melos
          run: dart pub global activate melos 8.6.0
        - name: Bootstrap
          run: melos bootstrap
        - name: Build APK
          working-directory: packages/app
          run: flutter build apk --debug
        - uses: actions/upload-artifact@v4
          with:
            name: android-debug-apk
            path: packages/app/build/app/outputs/flutter-apk/app-debug.apk

    build-linux:
      runs-on: ubuntu-22.04
      steps:
        - uses: actions/checkout@v4.2.2
        - name: Install Linux build dependencies
          run: |
            sudo apt-get update
            sudo apt-get install -y \
              clang cmake ninja-build pkg-config \
              libgtk-3-dev libwebkit2gtk-4.0-dev \
              liblzma-dev libstdc++-12-dev
        - uses: subosito/flutter-action@v2
          with:
            flutter-version: "3.44.6"
            channel: stable
            cache: true
        - name: Install melos
          run: dart pub global activate melos 8.6.0
        - name: Bootstrap
          run: melos bootstrap
        - name: Build Linux
          working-directory: packages/app
          run: flutter build linux
        - uses: actions/upload-artifact@v4
          with:
            name: linux-build
            path: packages/app/build/linux/x64/release/bundle/

    build-macos:
      runs-on: macos-latest
      steps:
        - uses: actions/checkout@v4.2.2
        - uses: subosito/flutter-action@v2
          with:
            flutter-version: "3.44.6"
            channel: stable
            cache: true
        - name: Install melos
          run: dart pub global activate melos 8.6.0
        - name: Bootstrap
          run: melos bootstrap
        - name: Build macOS
          working-directory: packages/app
          run: flutter build macos
        - uses: actions/upload-artifact@v4
          with:
            name: macos-build
            path: packages/app/build/macos/Build/Products/Release/

    build-windows:
      runs-on: windows-latest
      steps:
        - uses: actions/checkout@v4.2.2
        - uses: subosito/flutter-action@v2
          with:
            flutter-version: "3.44.6"
            channel: stable
            cache: true
        - name: Install melos
          run: dart pub global activate melos 8.6.0
        - name: Bootstrap
          run: melos bootstrap
        - name: Build Windows
          working-directory: packages/app
          run: flutter build windows
        - uses: actions/upload-artifact@v4
          with:
            name: windows-build
            path: packages/app/build/windows/x64/runner/Release/

    deploy:
      needs: [lint, build-signaling-image, build-web-image]
      if: github.ref == 'refs/heads/main'
      runs-on: ubuntu-latest
      steps:
        - name: Trigger Dokploy redeploy
          run: curl -f -X POST "${{ secrets.DOKPLOY_WEBHOOK_URL }}"
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add .github/workflows/ci.yml
  git commit -m "ci: multi-platform builds + GHCR image push + Dokploy deploy"
  ```

---

## Chunk 3: Secrets + Dokploy setup (manual steps before pushing)

Do these **before** pushing to main — Dokploy needs to be configured so the deploy webhook has somewhere to land.

### Task 5: GitHub secrets

- [ ] **Step 1: Create GHCR_TOKEN**

  GitHub → Settings → Developer settings → Personal access tokens → Classic.
  Scope: `write:packages`. Name it `GHCR_TOKEN`.

- [ ] **Step 2: Add GHCR_TOKEN to the repo**

  GitHub → `hxc-gxc/PeerTFT` → Settings → Secrets and variables → Actions → New secret:
  - Name: `GHCR_TOKEN`, Value: the PAT from Step 1

  (`DOKPLOY_WEBHOOK_URL` will be added in Task 6 after Dokploy is set up.)

### Task 6: Dokploy project setup

- [ ] **Step 1: Create Dokploy project**

  In Dokploy UI:
  - New project → Docker Compose
  - Source: GitHub repo `hxc-gxc/PeerTFT`, branch `main`
  - Compose file: `docker-compose.yml`

- [ ] **Step 2: Configure domains**

  In the project's domain panel:
  - `signal.noredflag.fr` → service `signaling`, port `8080`, enable HTTPS
  - `peer.noredflag.fr` → service `web`, port `80`, enable HTTPS

- [ ] **Step 3: Open UDP 3478 on the VPS**

  ```bash
  ufw allow 3478/udp
  ```

- [ ] **Step 4: Copy the Redeploy webhook URL**

  In Dokploy: project → Deployments tab → Webhook section → copy the **Redeploy** webhook URL.
  Add it as GitHub secret `DOKPLOY_WEBHOOK_URL`.

---

## Chunk 4: Push, make images public, verify

**IMPORTANT ordering:** The first CI push creates the GHCR packages as private by default. Dokploy's deploy webhook will fire and fail with 401 on the first run. That's expected — follow the steps below to fix it before Dokploy retries.

### Task 7: First push and verification

- [ ] **Step 1: Push to main**

  ```bash
  git push
  ```

- [ ] **Step 2: Watch CI — wait for image jobs to finish**

  GitHub → Actions → latest run. Wait for `build-signaling-image` and `build-web-image` to show ✅.
  The `deploy` job will likely fail (401) on this first run — that's fine.

- [ ] **Step 3: Make GHCR packages public**

  GitHub → your profile → Packages → `peertft-signaling` → Package settings → Change visibility → **Public**.
  Repeat for `peertft-web`.

  Do this immediately after Step 2, before triggering any manual redeploy.

- [ ] **Step 4: Trigger Dokploy redeploy manually**

  In Dokploy UI: project → Deployments → Deploy (or re-trigger). This pulls the now-public images and starts all 3 containers.

  Alternatively, re-run just the `deploy` job from GitHub Actions → the failed run → Re-run failed jobs.

- [ ] **Step 5: Confirm all platform artifacts**

  Back in GitHub Actions, confirm all jobs green:
  - `lint` ✅
  - `build-android` ✅ — download `android-debug-apk` artifact
  - `build-linux` ✅ — download `linux-build` artifact
  - `build-macos` ✅ — download `macos-build` artifact
  - `build-windows` ✅ — download `windows-build` artifact

- [ ] **Step 6: Verify signaling endpoint**

  ```bash
  # Requires wscat: npm i -g wscat
  wscat -c wss://signal.noredflag.fr/ws
  ```

  Expected: `Connected (press CTRL+C to quit)` — server accepted the WebSocket upgrade.

- [ ] **Step 7: Cross-network P2P test**

  1. Open `https://peer.noredflag.fr` on **Device A** (laptop on WiFi)
  2. Open `https://peer.noredflag.fr` on **Device B** (phone on mobile data — different network)
  3. Device A: pick a file → copy the room code
  4. Device B: paste the room code and connect
  5. Transfer completes ✅ — P2P confirmed

  If the transfer fails with "Connexion directe impossible": this is the expected behaviour for symmetric NAT (~15% of networks). The explicit error message confirms signaling and ICE are working — only NAT type is blocking direct P2P.

- [ ] **Step 8: Install and test Android APK**

  Download `android-debug-apk` from CI artifacts → transfer to Android device → enable "Install from unknown sources" → install → repeat the cross-network test using the native app.
