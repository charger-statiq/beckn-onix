#!/bin/bash
# Render deploy/npci-v0.9.5/config/onix-bpp/*.tmpl + routing into .rendered/ (gitignored, 0600).
# The v0.9.5 image does not expand ${VAR}, so the private keys must be literal in the file it reads.
# Required env:  ONIX_SIGNING_PRIVATE_KEY  ONIX_ENCR_PRIVATE_KEY      (raw 32-byte base64; from AWS SM dev/beckn-onix)
# Optional env:  REDIS_ADDR (default redis-onix-bpp:6379)  REDIS_USE_TLS=true|false (default false)  HUB_OCPI_BECKN_URL (default http://hub-ocpi.statiq-dev:5000/beckn)
#                CDS_PUBLISH_BASE_URL (default http://uat-cds.ubc.nbsl.org.in)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${ONIX_SIGNING_PRIVATE_KEY:?set ONIX_SIGNING_PRIVATE_KEY}"
: "${ONIX_ENCR_PRIVATE_KEY:?set ONIX_ENCR_PRIVATE_KEY}"
REDIS_ADDR=${REDIS_ADDR:-redis-onix-bpp:6379}
REDIS_USE_TLS=${REDIS_USE_TLS:-false}
HUB_OCPI_BECKN_URL=${HUB_OCPI_BECKN_URL:-http://hub-ocpi.statiq-dev:5000/beckn}
CDS_PUBLISH_BASE_URL=${CDS_PUBLISH_BASE_URL:-http://uat-cds.ubc.nbsl.org.in}
OUT="$HERE/.rendered"
rm -rf "$OUT"; mkdir -p "$OUT"; chmod 700 "$OUT"
sed -e "s|__ONIX_SIGNING_PRIVATE_KEY__|$ONIX_SIGNING_PRIVATE_KEY|g" \
    -e "s|__ONIX_ENCR_PRIVATE_KEY__|$ONIX_ENCR_PRIVATE_KEY|g" \
    -e "s|__REDIS_ADDR__|$REDIS_ADDR|g" \
    -e "s|__REDIS_USE_TLS__|$REDIS_USE_TLS|g" \
    "$HERE/config/onix-bpp/adapter.yaml.tmpl" > "$OUT/adapter.yaml"
sed -e "s|__HUB_OCPI_BECKN_URL__|$HUB_OCPI_BECKN_URL|g" "$HERE/config/onix-bpp/bpp_receiver_routing.yaml" > "$OUT/bpp_receiver_routing.yaml"
sed -e "s|__CDS_PUBLISH_BASE_URL__|$CDS_PUBLISH_BASE_URL|g" "$HERE/config/onix-bpp/bpp_caller_routing.yaml" > "$OUT/bpp_caller_routing.yaml"
cp "$HERE/config/onix-bpp/audit-fields.yaml" "$OUT/"
chmod 600 "$OUT"/*
if grep -q "__[A-Z_]*__" "$OUT"/*.yaml; then echo "unrendered token left:"; grep -n "__[A-Z_]*__" "$OUT"/*.yaml; exit 1; fi
echo "rendered -> $OUT  (redis=$REDIS_ADDR tls=$REDIS_USE_TLS, hub=$HUB_OCPI_BECKN_URL, cds=$CDS_PUBLISH_BASE_URL)"
