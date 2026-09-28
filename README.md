# Statiq BPP ONIX deployment

Statiq runs the ONIX image NPCI's UBC sandbox runs, `manendrapalsingh/onix-adapter:v0.9.5`,
with our own config. Nothing here is built; the image is pulled and the config is rendered.

Everything lives in [`deploy/npci-v0.9.5/`](deploy/npci-v0.9.5/):

- `README.md` there: what the config is, how it differs from NPCI's, runtime facts about the image
- `DEPLOY.md` there: the devops runbook for `statiq-dev` (Kubernetes)
- `DEPLOY-COMPOSE.md` there: the same thing on one machine with Docker Compose

Upstream for the config: https://github.com/bhim/ubc-ev-sandbox, folder `onix-adaptor/`, commit `f705bf2`.

This repo began as a fork of `beckn-one/beckn-onix` with our own Go build (secrets loader, Dockerfile).
That code was removed on 2026-09-18 and is still in history at `c7e5cc1` if current ONIX ever becomes usable
for UBC traffic again.

## CI/CD (AWS CodePipeline -> CodeDeploy)

Pipeline is Source -> Deploy, no build stage (nothing is built). CodeDeploy copies the repo to
`/opt/beckn-onix` on the host and runs the hooks in [`scripts/`](scripts/) per [`appspec.yml`](appspec.yml):
`docker compose down` -> `pull` -> `up -d` in `deploy/npci-v0.9.5`, then waits for `onix-bpp-plugin` to be healthy.

Host needs: CodeDeploy agent, an instance role with `secretsmanager:GetSecretValue` on `dev/beckn-onix`
(IMDSv2 hop limit 2 so containers can use it), and outbound access to Docker Hub and raw.githubusercontent.com.
Don't also run compose by hand from another clone: the container names are fixed and will collide.
