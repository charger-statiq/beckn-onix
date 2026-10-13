#!/bin/bash
# Fetch the ONIX secret from AWS Secrets Manager and render the config.
# The secret holds everything that differs per environment: the two private keys (required) and,
# optionally, ONIX_SUBSCRIBER_ID, ONIX_KEY_ID, ONIX_SIGNING_PUBLIC_KEY, ONIX_ENCR_PUBLIC_KEY,
# HUB_OCPI_BECKN_URL, CDS_PUBLISH_BASE_URL. Precedence: host env (non-empty) > secret > render default.
# Runs as the `onix-config-init` service in docker-compose.yml before ONIX starts, so a
# stack restart picks up a rotated secret with no manual export. Also fine to run by hand
# on a host that has the aws cli and jq.
#
# Env:  ONIX_SECRET_ID  (default dev/beckn-onix)   AWS_REGION (default ap-south-1)
#       AWS credentials from the usual chain: env vars, ~/.aws, or the instance role.
#       Everything render-config.sh accepts (REDIS_ADDR, HUB_OCPI_BECKN_URL, ...) passes through;
#       a non-empty host value overrides the secret, an empty one (compose's `${VAR:-}`) does not.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ONIX_SECRET_ID=${ONIX_SECRET_ID:-dev/beckn-onix}
export AWS_REGION=${AWS_REGION:-ap-south-1}
export AWS_DEFAULT_REGION=$AWS_REGION

# Compose passes `${VAR:-}` through as an empty string; the aws cli treats an empty
# AWS_ACCESS_KEY_ID as "partial credentials" and refuses to fall back to the instance role.
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE \
         ONIX_SUBSCRIBER_ID ONIX_KEY_ID ONIX_SIGNING_PUBLIC_KEY ONIX_ENCR_PUBLIC_KEY HUB_OCPI_BECKN_URL CDS_PUBLISH_BASE_URL; do
  [ -z "${!v:-}" ] && unset "$v"
done

echo "fetching $ONIX_SECRET_ID from Secrets Manager ($AWS_REGION)"
SECRET=$(aws secretsmanager get-secret-value --secret-id "$ONIX_SECRET_ID" --query SecretString --output text)

export ONIX_SIGNING_PRIVATE_KEY=$(jq -er '.ONIX_SIGNING_PRIVATE_KEY' <<<"$SECRET")
export ONIX_ENCR_PRIVATE_KEY=$(jq -er '.ONIX_ENCR_PRIVATE_KEY' <<<"$SECRET")

# Per-environment values: taken from the secret unless the host env already sets them.
for v in ONIX_SUBSCRIBER_ID ONIX_KEY_ID ONIX_SIGNING_PUBLIC_KEY ONIX_ENCR_PUBLIC_KEY HUB_OCPI_BECKN_URL CDS_PUBLISH_BASE_URL; do
  if [ -z "${!v:-}" ]; then
    val=$(jq -r --arg k "$v" '.[$k] // empty' <<<"$SECRET")
    [ -n "$val" ] && export "$v=$val"
  fi
done
unset SECRET val
echo "identity: subscriber=${ONIX_SUBSCRIBER_ID:-<render default>} keyId=${ONIX_KEY_ID:-<render default>} hub=${HUB_OCPI_BECKN_URL:-<render default>} cds=${CDS_PUBLISH_BASE_URL:-<render default>}"

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
