# Running ONIX v0.9.5 with Docker Compose

For a single machine (laptop or a VM). The Kubernetes route is in [`DEPLOY.md`](DEPLOY.md).

Nothing is built. The compose file pulls NPCI's image `manendrapalsingh/onix-adapter:v0.9.5`
and mounts our rendered config into it.

Four containers come up:

| container | what it is | port |
|---|---|---|
| `onix-config-init` | one-shot: fetches the private keys from AWS Secrets Manager and renders the config, then exits | none |
| `onix-bpp-plugin` | ONIX itself; waits for the init to finish | 8002, published on the host |
| `redis-onix-bpp` | Redis, mandatory (no Redis, no boot) | internal only |
| `otel-collector-bpp` | OpenTelemetry collector | internal only |

## 1. Give the host access to the secret

The private keys live in AWS Secrets Manager under `dev/beckn-onix` (override with
`ONIX_SECRET_ID`). `onix-config-init` reads them on every start, so the host needs permission to
call `secretsmanager:GetSecretValue` on that one secret. Either:

- **Instance role** (preferred). Attach a role with that permission to the VM. If the instance
  uses IMDSv2, set its hop limit to 2, otherwise containers on the bridge network cannot reach
  the metadata endpoint.
- **Keys in a `.env` file** next to `docker-compose.yml` (gitignored):

  ```
  AWS_ACCESS_KEY_ID=...
  AWS_SECRET_ACCESS_KEY=...
  ```

Nobody needs to see or copy the key values. They go from Secrets Manager straight into
`.rendered/adapter.yaml` inside the container.

## 2. Start

```bash
docker compose up -d
```

First run pulls about 1 GB of images, so give it a few minutes. `onix-config-init` runs first,
prints `rendered -> /work/.rendered (...)` and exits 0; only then does `onix-bpp-plugin` start.

Overrides, all optional, exported before `up` or put in `.env`:

| variable | default |
|---|---|
| `ONIX_SECRET_ID` | `dev/beckn-onix` |
| `AWS_REGION` | `ap-south-1` |
| `REDIS_ADDR` | `redis-onix-bpp:6379` (the compose Redis) |
| `REDIS_USE_TLS` | `false` |
| `HUB_OCPI_BECKN_URL` | `https://dev.roaming.evlinq.in/beckn` |
| `CDS_PUBLISH_BASE_URL` | `http://uat-cds.ubc.nbsl.org.in` |

## 3. After rotating the keys

Update the secret in Secrets Manager, then:

```bash
docker compose up -d --force-recreate onix-config-init onix-bpp-plugin
```

That re-runs the init (fresh render from the secret) and restarts ONIX on the new file.
`docker compose restart onix-bpp-plugin` alone is **not** enough: it does not re-run the init, so
ONIX would boot on the old file.

To check what ONIX is actually signing with, without printing the key:

```bash
docker compose logs onix-config-init | tail -2                     # should say rendered -> ...
sudo grep signingPrivateKey .rendered/adapter.yaml | awk '{print $2}' | sort -u | wc -l   # 1
```

The signature on any callback ONIX sends must verify with the public key registered in DeDi.
Hub-OCPI's `docs/npci-poc/tools/signed_send.sh` plus the ES log is the end-to-end check.

### Manual fallback (no AWS access from the host)

`render-config.sh` still works on its own. Export the two keys and render before `up`:

```bash
export ONIX_SIGNING_PRIVATE_KEY=...   # from Secrets Manager, raw 32-byte base64
export ONIX_ENCR_PRIVATE_KEY=...
./render-config.sh
docker compose up -d --no-deps onix-bpp-plugin redis-onix-bpp otel-collector-bpp
```

`--no-deps` skips `onix-config-init`, which would fail without AWS access and block ONIX.

## 4. Check it worked

```bash
docker compose ps
```

Wait for `onix-bpp-plugin` to say `(healthy)`. The healthcheck has a 45 second start period, so
`(health: starting)` right after boot is normal. `onix-config-init` shows `Exited (0)`; that is
correct for a one-shot.

```bash
curl -s http://localhost:8002/health
# {"status":"ok","service":"beckn-adapter"}
```

Then check the logs for the lines that prove each plugin loaded:

```bash
docker compose logs onix-bpp-plugin | grep -iE "keyset|steps initialized|Cache connection|DeDi Registry client"
```

You want all four:

```
Cache connection to Redis established successfully
DeDi Registry client connection established successfully
Successfully loaded keyset from configuration with keyID: 76EU8q...
Processor steps initialized: [validateSign addRoute validateSchema]
Processor steps initialized: [validateSchema addRoute sign]
```

Last, confirm the receiver is answering:

```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{}' http://localhost:8002/bpp/receiver/select
# context field not found or invalid.
```

That error is the correct answer to an empty body. It means the route exists and the request
reached the processor.

## 5. Point Hub-OCPI at it

| Hub-OCPI setting | value |
|---|---|
| `BECKN_ONIX_CLIENT_URL` | `http://localhost:8002/bpp/caller` |
| `BECKN_BPP_URI` | the public URL that reaches this host, plus `/bpp/receiver` |

`BECKN_BPP_URI` must be reachable from the outside, because it is what other network
participants call back on. `localhost` will not work there.

## Everyday commands

```bash
docker compose logs -f onix-bpp-plugin                                    # follow the logs
docker compose up -d --force-recreate onix-config-init onix-bpp-plugin    # re-render from the secret + restart ONIX
docker compose restart onix-bpp-plugin                                    # restart ONIX on the current file (no re-render)
docker compose down                                                       # stop everything, keep images
docker compose down -v                                                    # also wipe the Redis data
```

ONIX reads its config once at boot. Any change to the secret or to the templates under
`config/onix-bpp/` needs the `--force-recreate` line above.

## When something goes wrong

**`onix-bpp-plugin` never starts, `onix-config-init` shows `Exited (1)` or `Exited (25x)`.** The
render failed, so compose held ONIX back on purpose. Read why:

```bash
docker compose logs onix-config-init
```

- `Unable to locate credentials` — the host has no AWS access. See step 1.
- `ResourceNotFoundException` — wrong `ONIX_SECRET_ID` or wrong region.
- `AccessDeniedException` — the role or keys cannot read this secret.
- `... is N chars, expected 44` — the value in the secret is not a raw 32-byte key.

**`docker compose ps` shows `Up` but nothing answers on 8002.** ONIX is crash looping. The
healthcheck catches this now, but always read the logs:

```bash
docker compose logs onix-bpp-plugin | grep '"level":"fatal"'
```

**`failed to load OpenAPI document ... i/o timeout`** — the container cannot reach the internet.
ONIX downloads the beckn schema at boot, so Docker needs outbound access to
`raw.githubusercontent.com`.

**Callbacks are rejected by the network with a signature error, but the receiver accepts
inbound.** The receiver checks *other* parties' keys from the registry, so it passes regardless;
only the caller uses our private key. The rendered file is stale. Run the `--force-recreate`
line and verify as in step 3.

**`rm -rf: Permission denied` from a manual `render-config.sh`** — `.rendered` was written by the
init container as root. Use `sudo rm -rf .rendered`, then render again, or just let the init do it.
