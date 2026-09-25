#!/usr/bin/env bash
set -euo pipefail
DIR=/opt/beckn-onix/deploy/npci-v0.9.5
cd "$DIR"
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

# The compose file hard-codes container_name, so a stack started manually from the old
# git-clone directory (different compose project) would block `up`. Remove those
# containers, and anything else holding host port 8002.
docker rm -f onix-config-init onix-bpp-plugin redis-onix-bpp otel-collector-bpp 2>/dev/null || true
docker ps -q --filter "publish=8002" | xargs -r docker rm -f

# Same as the manual `docker-compose up -d`. If onix-config-init can't render (no AWS
# access, bad secret) compose refuses to start ONIX and this exits non-zero -> deploy fails.
$DC -p beckn-onix up -d --remove-orphans
docker image prune -f
