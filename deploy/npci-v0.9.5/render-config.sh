#!/bin/bash
# Render deploy/npci-v0.9.5/config/onix-bpp/*.tmpl + routing into .rendered/ (gitignored, 0600).
# The v0.9.5 image does not expand ${VAR}, so the private keys must be literal in the file it reads.
# Required env:  ONIX_SIGNING_PRIVATE_KEY  ONIX_ENCR_PRIVATE_KEY      (raw 32-byte base64; from AWS SM dev/beckn-onix)
# Optional env:  REDIS_ADDR (default redis-onix-bpp:6379)  REDIS_USE_TLS=true|false (default false)  HUB_OCPI_BECKN_URL (default https://dev.roaming.evlinq.in/beckn)
#                CDS_PUBLISH_BASE_URL (default http://uat-cds.ubc.nbsl.org.in)
#                ONIX_SUBSCRIBER_ID  ONIX_KEY_ID  ONIX_SIGNING_PUBLIC_KEY  ONIX_ENCR_PUBLIC_KEY   (our DeDi record; defaults = dev)
# Every value differs per environment. With compose they come from the <env>/beckn-onix secret via fetch-and-render.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${ONIX_SIGNING_PRIVATE_KEY:?set ONIX_SIGNING_PRIVATE_KEY}"
: "${ONIX_ENCR_PRIVATE_KEY:?set ONIX_ENCR_PRIVATE_KEY}"
REDIS_ADDR=${REDIS_ADDR:-redis-onix-bpp:6379}
REDIS_USE_TLS=${REDIS_USE_TLS:-false}
HUB_OCPI_BECKN_URL=${HUB_OCPI_BECKN_URL:-https://dev.roaming.evlinq.in/beckn}
CDS_PUBLISH_BASE_URL=${CDS_PUBLISH_BASE_URL:-http://uat-cds.ubc.nbsl.org.in}
ONIX_SUBSCRIBER_ID=${ONIX_SUBSCRIBER_ID:-cert-statiq.evlinq.in}
ONIX_KEY_ID=${ONIX_KEY_ID:-76EU8qiBwfUBmq3RN18KXQt5DsqEumw2hbFK4RuqpaKfvdb2RiQnnX}
ONIX_SIGNING_PUBLIC_KEY=${ONIX_SIGNING_PUBLIC_KEY:-d1n58ic3+qi2mvw5r/4tlf2F+bI2ajfluOxVdtf6J2Y=}
ONIX_ENCR_PUBLIC_KEY=${ONIX_ENCR_PUBLIC_KEY:-kvL8Go5zSKd9MaMvMVJn7zzYEF/AZHQGSxk6qVqoFl0=}
# A raw ed25519/x25519 key is 32 bytes = 44 base64 chars. The public halves must match the DeDi record for ONIX_KEY_ID.
for v in ONIX_SIGNING_PUBLIC_KEY ONIX_ENCR_PUBLIC_KEY; do
  val=${!v}
  if [ "${#val}" -ne 44 ]; then echo "$v is ${#val} chars, expected 44 (raw 32-byte key, base64)" >&2; exit 1; fi
done
unset val
OUT="$HERE/.rendered"
rm -rf "$OUT"; mkdir -p "$OUT"; chmod 700 "$OUT"
sed -e "s|__ONIX_SIGNING_PRIVATE_KEY__|$ONIX_SIGNING_PRIVATE_KEY|g" \
    -e "s|__ONIX_ENCR_PRIVATE_KEY__|$ONIX_ENCR_PRIVATE_KEY|g" \
    -e "s|__REDIS_ADDR__|$REDIS_ADDR|g" \
    -e "s|__REDIS_USE_TLS__|$REDIS_USE_TLS|g" \
    -e "s|__ONIX_SUBSCRIBER_ID__|$ONIX_SUBSCRIBER_ID|g" \
    -e "s|__ONIX_KEY_ID__|$ONIX_KEY_ID|g" \
    -e "s|__ONIX_SIGNING_PUBLIC_KEY__|$ONIX_SIGNING_PUBLIC_KEY|g" \
    -e "s|__ONIX_ENCR_PUBLIC_KEY__|$ONIX_ENCR_PUBLIC_KEY|g" \
    "$HERE/config/onix-bpp/adapter.yaml.tmpl" > "$OUT/adapter.yaml"
sed -e "s|__HUB_OCPI_BECKN_URL__|$HUB_OCPI_BECKN_URL|g" "$HERE/config/onix-bpp/bpp_receiver_routing.yaml" > "$OUT/bpp_receiver_routing.yaml"
sed -e "s|__CDS_PUBLISH_BASE_URL__|$CDS_PUBLISH_BASE_URL|g" "$HERE/config/onix-bpp/bpp_caller_routing.yaml" > "$OUT/bpp_caller_routing.yaml"
cp "$HERE/config/onix-bpp/audit-fields.yaml" "$OUT/"
chmod 600 "$OUT"/*
if grep -q "__[A-Z_]*__" "$OUT"/*.yaml; then echo "unrendered token left:"; grep -n "__[A-Z_]*__" "$OUT"/*.yaml; exit 1; fi
echo "rendered -> $OUT  (subscriber=$ONIX_SUBSCRIBER_ID keyId=${ONIX_KEY_ID:0:8}…, redis=$REDIS_ADDR tls=$REDIS_USE_TLS, hub=$HUB_OCPI_BECKN_URL, cds=$CDS_PUBLISH_BASE_URL)"
