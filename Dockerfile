# syntax=docker/dockerfile:1

# ── Stage 1: Build ────────────────────────────────────────────

# ── Stage 1: Build ────────────────────────────────────────────
FROM alpine:3.23 AS builder

# Alpine 3.23 hiện tại cung cấp Zig 0.15.2-r0, khớp với yêu cầu project
RUN apk add --no-cache zig musl-dev

WORKDIR /app

# Thay vì copy từng file, hãy copy toàn bộ thư mục hiện tại
# Điều này đảm bảo thư mục vendor/ và các tài nguyên khác được đưa vào
COPY . .

# Tiến hành build
RUN zig build -Doptimize=ReleaseSmall

# ── Stage 2: Config Prep ─────────────────────────────────────
FROM busybox:1.37 AS config

RUN mkdir -p /nullclaw-data/.nullclaw /nullclaw-data/workspace

# Tạo file config.json theo cấu trúc chuẩn v2026 (Nested JSON)
RUN cat > /nullclaw-data/.nullclaw/config.json << 'EOF'
{
  "models": {
    "providers": {
      "openrouter": { 
        "api_key": "" 
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { 
        "primary": "openrouter/openai/gpt-5-nano" 
      },
      "temperature": 0.7
    }
  },
  "gateway": {
    "port": 3000,
    "host": "::",
    "allow_public_bind": true,
    "require_pairing": false
  }
}
EOF

# Default runtime runs as non-root (uid/gid 65534).
# Keep writable ownership for HOME/workspace in safe mode.
RUN chown -R 65534:65534 /nullclaw-data

# ── Stage 3: Runtime Base (shared) ────────────────────────────
FROM alpine:3.23 AS release-base

LABEL org.opencontainers.image.source=https://github.com/nullclaw/nullclaw

RUN apk add --no-cache ca-certificates curl tzdata

COPY --from=builder /app/zig-out/bin/nullclaw /usr/local/bin/nullclaw
COPY --from=config /nullclaw-data /nullclaw-data

ENV NULLCLAW_WORKSPACE=/nullclaw-data/workspace
ENV HOME=/nullclaw-data
ENV NULLCLAW_GATEWAY_PORT=3000

WORKDIR /nullclaw-data
EXPOSE 3000
ENTRYPOINT ["nullclaw"]
CMD ["gateway", "--port", "3000", "--host", "::"]

# Optional autonomous mode (explicit opt-in):
#   docker build --target release-root -t nullclaw:root .
FROM release-base AS release-root
USER 0:0

# Safe default image (used when no --target is provided)
FROM release-base AS release
USER 65534:65534
