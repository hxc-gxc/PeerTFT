# --- Stage 1: build a native AOT executable -------------------------------
FROM dart:stable AS build
WORKDIR /app

# Copy the whole monorepo context so the `shared` path dependency resolves;
# see docker-compose.yml, which sets this Dockerfile's build context to the
# repository root.
COPY packages/shared ./packages/shared
COPY packages/signaling_server ./packages/signaling_server
WORKDIR /app/packages/signaling_server

RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# --- Stage 2: minimal runtime ----------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/packages/signaling_server/bin/server /app/server

EXPOSE 8080
ENTRYPOINT ["/app/server"]
