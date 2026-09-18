# Running ONIX v0.9.5 with Docker Compose

For a single machine (laptop or a VM). The Kubernetes route is in [`DEPLOY.md`](DEPLOY.md).

Nothing is built. The compose file pulls NPCI's image `manendrapalsingh/onix-adapter:v0.9.5`
and mounts our rendered config into it.

Three containers come up:

| container | what it is | port |
|---|---|---|
| `onix-bpp-plugin` | ONIX itself | 8002, published on the host |
| `redis-onix-bpp` | Redis, mandatory (no Redis, no boot) | internal only |
| `otel-collector-bpp` | OpenTelemetry collector | internal only |

## 0. Before you start

**Docker must be able to reach the internet.** ONIX downloads the beckn schema at boot and
dies if it cannot. Check it:

```bash
docker run --rm alpine sh -c 'nslookup raw.githubusercontent.com && echo DNS-OK'
```

If that times out, check IP forwarding on the host:

```bash
cat /proc/sys/net/ipv4/ip_forward     # must be 1
sudo sysctl -w net.ipv4.ip_forward=1  # fix for now
```

To make it stick, uncomment `net.ipv4.ip_forward=1` in `/etc/sysctl.conf`. A VPN client can
switch this back off, so check again after connecting to a VPN.

**Port 8002 must be free** on the host.

## 1. Get the two private keys

They live in AWS Secrets Manager under `dev/beckn-onix`:

```bash
cd deploy/npci-v0.9.5
export ONIX_SIGNING_PRIVATE_KEY=$(aws secretsmanager get-secret-value --secret-id dev/beckn-onix --query SecretString --output text | jq -r .ONIX_SIGNING_PRIVATE_KEY)
export ONIX_ENCR_PRIVATE_KEY=$(aws secretsmanager get-secret-value --secret-id dev/beckn-onix --query SecretString --output text | jq -r .ONIX_ENCR_PRIVATE_KEY)
```

## 2. Render the config

```bash
./render-config.sh
```

This writes `.rendered/` (gitignored, mode 600). It holds the private keys in plain text, so do
not copy it anywhere. See [`render-config.sh`](render-config.sh) for what each token does.

Defaults it uses, override by exporting before the run:

| variable | default |
|---|---|
| `REDIS_ADDR` | `redis-onix-bpp:6379` (the compose Redis) |
| `REDIS_USE_TLS` | `false` |
| `HUB_OCPI_BECKN_URL` | `https://dev.roaming.evlinq.in/beckn` |
| `CDS_PUBLISH_BASE_URL` | `http://uat-cds.ubc.nbsl.org.in` |

**Always render before `docker compose up`.** If you start compose first, Docker creates
`./.rendered` as an empty folder owned by root, and the next `render-config.sh` run fails on it.

## 3. Start

```bash
docker compose up -d
```

First run pulls about 1 GB of images, so give it a few minutes.

## 4. Check it worked

```bash
docker compose ps
```

Wait for `onix-bpp-plugin` to say `(healthy)`. The healthcheck has a 45 second start period, so
`(health: starting)` right after boot is normal.

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
docker compose logs -f onix-bpp-plugin     # follow the logs
docker compose restart onix-bpp-plugin     # restart just ONIX
docker compose down                        # stop everything, keep images
docker compose down -v                     # also wipe the Redis data
```

After changing any config or rotating keys, re-render and restart:

```bash
./render-config.sh && docker compose restart onix-bpp-plugin
```

ONIX reads its config once at boot, so a restart is required. A `docker compose up -d` alone
will not pick up a new render.

## When something goes wrong

**`docker compose ps` shows `Up` but nothing answers on 8002.** ONIX is crash looping. The
healthcheck catches this now, but always read the logs:

```bash
docker compose logs onix-bpp-plugin | grep '"level":"fatal"'
```

**`failed to load OpenAPI document ... i/o timeout`** — the container has no internet. Go back
to step 0.

**`render-config.sh` says `set ONIX_SIGNING_PRIVATE_KEY`** — the exports from step 1 are gone.
They only last for the current shell.

**`rm -rf: Permission denied` from render-config.sh** — you ran compose before rendering. Fix
it with `sudo rm -rf .rendered`, then render again.

**`unrendered token left:`** — a token in the template has no matching replacement in
`render-config.sh`. The script prints the file and line.

**The otel collector logs export failures** to `otel-collector-network:4318`. That host is not
part of this compose file. Harmless; ONIX is unaffected.

## A note on secrets

`docker-compose.yml` has the Redis password in plain text. That is fine here because Redis is
not published outside the compose network. The real secrets are the two private keys, and they
only ever exist in `.rendered/`, which git ignores.

Delete `.rendered/` when you are done on a shared machine.
