#!/bin/bash
# Run the ONIX adapter natively from this checkout, reading config/onix/adapter.yaml as it is on disk.
#   ./run-local.sh                  start on :8080 with dummy signing keys
#   ./run-local.sh --build-plugins  rebuild ./plugins/*.so first (needed once, and after plugin code changes)
# Real keys: export ONIX_SIGNING_PRIVATE_KEY / ONIX_ENCR_PRIVATE_KEY (or SECRET_ID + AWS creds) before running.
set -e
REPO=$(cd "$(dirname "$0")" && pwd)
cd "$REPO"

if [ "$1" = "--build-plugins" ] || [ -z "$(ls plugins/*.so 2>/dev/null)" ]; then
  echo ">> building plugins into ./plugins (a few minutes)"
  ./install/build-plugins.sh
fi

# The shipped config uses the container's /app paths; rewrite them to this checkout.
mkdir -p .local
sed "s|/app/|$REPO/|g" config/onix/adapter.yaml > .local/adapter.yaml

# Dummy 32-byte keys so the key manager starts without AWS; real ones from the environment win.
export ONIX_SIGNING_PRIVATE_KEY="${ONIX_SIGNING_PRIVATE_KEY:-$(head -c 32 /dev/urandom | base64)}"
export ONIX_ENCR_PRIVATE_KEY="${ONIX_ENCR_PRIVATE_KEY:-$(head -c 32 /dev/urandom | base64)}"

echo ">> config: .local/adapter.yaml (generated from config/onix/adapter.yaml)"
echo ">> server: http://localhost:8080   (Ctrl-C to stop)"
exec go run ./cmd/adapter --config .local/adapter.yaml
