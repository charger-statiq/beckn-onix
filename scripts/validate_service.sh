#!/usr/bin/env bash
# Wait for the compose healthcheck (45s start period) to report healthy.
# Fails the deployment -- and prints why -- if it doesn't within ~4 minutes.
for i in $(seq 1 48); do
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' onix-bpp-plugin 2>/dev/null || echo missing)
  if [ "$status" = "healthy" ]; then
    echo "onix-bpp-plugin is healthy"
    exit 0
  fi
  echo "waiting for onix-bpp-plugin ($status) ..."
  sleep 5
done

echo "onix-bpp-plugin did not become healthy" >&2
echo "--- onix-config-init ---" >&2;  docker logs --tail 30  onix-config-init 2>&1 | grep -v -i privatekey >&2 || true
echo "--- onix-bpp-plugin ---" >&2;   docker logs --tail 100 onix-bpp-plugin  2>&1 | grep -v -i privatekey >&2 || true
exit 1
