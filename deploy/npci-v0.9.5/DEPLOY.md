# Deploying ONIX v0.9.5 to dev (statiq-dev) -- steps for devops

Replaces the Jenkins "build Dockerfile -> push ECR -> restart" flow. Nothing is built any more:
NPCI's prebuilt image runs with our config. All commands run against the microK8s cluster, namespace `statiq-dev`.

## 0. One-time

```bash
# Redis password (any value; the same secret feeds both Redis and ONIX)
kubectl -n statiq-dev create secret generic onix-redis --from-literal=password="$(openssl rand -hex 16)"

# Optional but recommended: mirror the image into our ECR so it cannot change or vanish
docker pull manendrapalsingh/onix-adapter:v0.9.5
docker tag  manendrapalsingh/onix-adapter:v0.9.5 871045590444.dkr.ecr.ap-south-1.amazonaws.com/onix-npci:v0.9.5
docker push 871045590444.dkr.ecr.ap-south-1.amazonaws.com/onix-npci:v0.9.5
# then set that image in k8s/deployment.yaml
```

## 1. Render the config (the two private keys come from AWS Secrets Manager `dev/beckn-onix`)

```bash
cd deploy/npci-v0.9.5
export ONIX_SIGNING_PRIVATE_KEY=$(aws secretsmanager get-secret-value --secret-id dev/beckn-onix --query SecretString --output text | jq -r .ONIX_SIGNING_PRIVATE_KEY)
export ONIX_ENCR_PRIVATE_KEY=$(aws secretsmanager get-secret-value --secret-id dev/beckn-onix --query SecretString --output text | jq -r .ONIX_ENCR_PRIVATE_KEY)
export HUB_OCPI_BECKN_URL=http://hub-ocpi.statiq-dev:5000/beckn      # in-cluster Hub-OCPI
export REDIS_ADDR=redis-onix-bpp:6379                                 # default, matches k8s/redis.yaml
./render-config.sh
```

## 2. Put the rendered files in a Secret (adapter.yaml now holds the private keys)

```bash
kubectl -n statiq-dev create secret generic onix-bpp-config --from-file=.rendered/ \
  --dry-run=client -o yaml | kubectl apply -f -
rm -rf .rendered
```

## 3. Apply the manifests

```bash
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/otel.yaml
kubectl apply -f k8s/service.yaml       # same name/NodePort 30087 as today, targetPort 8080 -> 8002
kubectl apply -f k8s/deployment.yaml    # same name `onix`, replaces the ECR image with NPCI's
kubectl -n statiq-dev rollout status deployment/onix
```

## 4. Verify

```bash
kubectl -n statiq-dev logs deploy/onix | grep -i "keyset\|Indexed action\|steps initialized\|fatal"
curl -s https://beckn-onix-dev.evlinq.in/health                                  # 200
curl -s -X POST https://beckn-onix-dev.evlinq.in/bpp/receiver/select -d '{}' -D - # 401, realm="cert-statiq.evlinq.in"
```

Expected log lines: `DeDi Registry client connection established`, `Successfully loaded keyset ... keyID: 76EU8q...`,
`Processor steps initialized: [validateSign addRoute validateSchema]` and `[validateSchema addRoute sign]`.

## 5. Hub-OCPI secrets (hub/ocpi in AWS SM) that point at ONIX

- `BECKN_ONIX_CLIENT_URL` = `http://onix.statiq-dev:8080/bpp/caller`   (in-cluster; the service port stays 8080)
- `BECKN_BPP_URI`         = `https://beckn-onix-dev.evlinq.in/bpp/receiver`

## Rotating keys or changing routing

Repeat steps 1-2, then `kubectl -n statiq-dev rollout restart deployment/onix`. The env-driven `SECRET_ID` loader of our
own build does not exist on this image; the Secret above is the only key path.

## Jenkins job `beckn-onix-dev`

Replace the build/push stages with steps 1-3 (render, secret, apply). The deploy stage's `kubectl` context stays the same.
