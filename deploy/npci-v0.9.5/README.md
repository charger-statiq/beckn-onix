# Statiq BPP ONIX on NPCI's prebuilt image (v0.9.5)

NPCI/NBSL asked us (2026-09-17) to run the ONIX their sandbox runs instead of our own build:

- upstream: https://github.com/bhim/ubc-ev-sandbox, folder `onix-adaptor/`, commit `f705bf2` (main, 2026-03-22)
- image:    `manendrapalsingh/onix-adapter:v0.9.5` (as in their `docker-compose-onix-bpp-plugin.yml`)

`onix-adaptor/` holds no source: two compose files plus `config/onix-bpp/` (adapter.yaml, two routing
files, audit-fields.yaml). This folder is that config with our values, and a compose file that mirrors theirs.

## What differs from their `config/onix-bpp/` (everything else is byte-identical)

| file | change |
|---|---|
| `adapter.yaml.tmpl` | `appName`; `subscriberId` / `networkParticipant` -> `cert-statiq.evlinq.in`; `keyId` -> our DeDi record id; public keys -> ours; private keys -> `__ONIX_*_PRIVATE_KEY__` tokens; registry -> their own commented `dediregistry` block, url `https://fabric.nfh.global/registry/dedi`; redis addr -> `__REDIS_ADDR__` |
| `bpp_receiver_routing.yaml` | target -> Hub-OCPI (`__HUB_OCPI_BECKN_URL__`); only the actions Hub-OCPI implements |
| `bpp_caller_routing.yaml` | `on_*` -> `bap` (as theirs, minus on_discover -> mock CDS); `catalog_publish` -> CDS url rule (`__CDS_PUBLISH_BASE_URL__`) |
| `audit-fields.yaml` | unchanged |

## Why a render step

The v0.9.5 image does not expand `${VAR}` in its config and has no secrets loader, so the private keys must be
literal in the file it reads. `render-config.sh` fills the tokens from the environment into `.rendered/`
(gitignored, mode 600). Treat `.rendered/adapter.yaml` as a secret: in Kubernetes mount it from a Secret, not a ConfigMap.

```bash
export ONIX_SIGNING_PRIVATE_KEY=...   # raw 32-byte base64, AWS SM dev/beckn-onix
export ONIX_ENCR_PRIVATE_KEY=...
export REDIS_ADDR=redis-onix-bpp:6379              # default
export HUB_OCPI_BECKN_URL=https://dev.roaming.evlinq.in/beckn   # default
./render-config.sh
docker compose up -d          # redis + onix v0.9.5 (:8002) + otel collector, same as NPCI's compose
```

Full step-by-step for the compose route, including checks and common problems, is in [`DEPLOY-COMPOSE.md`](DEPLOY-COMPOSE.md).

## Runtime facts (verified 2026-09-17)

- Boots with `validateSchema` on and the rc spec URL: v0.9.5's parser accepts that file; current beckn-onix main does not.
- Extended `@context` validation works on this image; keep `extendedSchema_enabled: "true"` as NPCI ships it.
- The Redis `cache` plugin is mandatory: no Redis, no boot.
- Ships `dediregistry.so`, so the real UAT registry works.
- Port 8002. Health `GET /health`. Receiver `/bpp/receiver/<action>`, caller `/bpp/caller/<on_action>`.
- Hub-OCPI side: `BECKN_ONIX_CLIENT_URL={onix}/bpp/caller`, `BECKN_BPP_URI={public onix}/bpp/receiver`.

## Not in this folder

The Go code in the rest of this repo (secret loader, Dockerfile) is our own ONIX build. It is unaffected and
stays available if NPCI fixes the spec upstream and current ONIX becomes usable again.
