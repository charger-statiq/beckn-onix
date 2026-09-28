#!/usr/bin/env bash
set -euo pipefail
DIR=/opt/beckn-onix/deploy/npci-v0.9.5
cd "$DIR"
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

# fetch-and-render.sh does `exec render-config.sh`, which needs the exec bit.
# The pipeline's source zip does not always preserve it.
chmod +x ./*.sh

# Public images only (Docker Hub), so no ECR login needed. Pulling here keeps the
# down->up gap in ApplicationStart short.
$DC -p beckn-onix pull
