#!/usr/bin/env bash
# Same as the manual `docker-compose down`. Never fails the deploy: on the very first
# deploy there is nothing to stop.
DIR=/opt/beckn-onix/deploy/npci-v0.9.5
cd "$DIR" 2>/dev/null || exit 0
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi
$DC -p beckn-onix down || true
