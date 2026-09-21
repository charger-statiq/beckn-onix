#!/bin/bash
# Fetch the two ONIX private keys from AWS Secrets Manager and render the config.
# Runs as the `onix-config-init` service in docker-compose.yml before ONIX starts, so a
# stack restart picks up a rotated secret with no manual export. Also fine to run by hand
# on a host that has the aws cli and jq.
#
# Env:  ONIX_SECRET_ID  (default dev/beckn-onix)   AWS_REGION (default ap-south-1)
#       AWS credentials from the usual chain: env vars, ~/.aws, or the instance role.
#       Everything render-config.sh accepts (REDIS_ADDR, HUB_OCPI_BECKN_URL, ...) passes through.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ONIX_SECRET_ID=${ONIX_SECRET_ID:-dev/beckn-onix}
export AWS_REGION=${AWS_REGION:-ap-south-1}
export AWS_DEFAULT_REGION=$AWS_REGION

# Compose passes `${VAR:-}` through as an empty string; the aws cli treats an empty
# AWS_ACCESS_KEY_ID as "partial credentials" and refuses to fall back to the instance role.
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE; do
  [ -z "${!v:-}" ] && unset "$v"
done

echo "fetching $ONIX_SECRET_ID from Secrets Manager ($AWS_REGION)"
SECRET=$(aws secretsmanager get-secret-value --secret-id "$ONIX_SECRET_ID" --query SecretString --output text)

export ONIX_SIGNING_PRIVATE_KEY=$(jq -er '.ONIX_SIGNING_PRIVATE_KEY' <<<"$SECRET")
export ONIX_ENCR_PRIVATE_KEY=$(jq -er '.ONIX_ENCR_PRIVATE_KEY' <<<"$SECRET")
unset SECRET

# A raw ed25519/x25519 key is 32 bytes = 44 base64 chars. Anything else is a bad secret value.
for v in ONIX_SIGNING_PRIVATE_KEY ONIX_ENCR_PRIVATE_KEY; do
  val=${!v}
  if [ "${#val}" -ne 44 ]; then
    echo "$v in $ONIX_SECRET_ID is ${#val} chars, expected 44 (raw 32-byte key, base64)" >&2
    exit 1
  fi
done
unset val

exec "$HERE/render-config.sh"
