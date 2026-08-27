FROM golang:1.26.1-bookworm AS builder

WORKDIR /workspace/app

# Copy only the necessary files and directories
COPY cmd/adapter/ ./cmd/adapter/
COPY core/ ./core/
COPY pkg/ ./pkg/
COPY install/build-plugins.sh ./install/build-plugins.sh
COPY install/scripts/version-vars.sh ./install/scripts/version-vars.sh
COPY go.mod .
COPY go.sum .

RUN go mod download

ARG ONIX_VERSION=dev
ARG GIT_COMMIT=unknown
ARG GIT_TREE_STATE=unknown
ARG BUILD_DATE=unknown

# Build main server
RUN go build -ldflags "-X github.com/beckn-one/beckn-onix/pkg/version.Version=${ONIX_VERSION} -X github.com/beckn-one/beckn-onix/pkg/version.GitCommit=${GIT_COMMIT} -X github.com/beckn-one/beckn-onix/pkg/version.GitTreeState=${GIT_TREE_STATE} -X github.com/beckn-one/beckn-onix/pkg/version.BuildDate=${BUILD_DATE}" -o server cmd/adapter/main.go

# Build the plugins into ./plugins
RUN chmod +x install/build-plugins.sh && \
    ONIX_VERSION="${ONIX_VERSION}" GIT_COMMIT="${GIT_COMMIT}" GIT_TREE_STATE="${GIT_TREE_STATE}" BUILD_DATE="${BUILD_DATE}" \
    ./install/build-plugins.sh

# Extract the JSON schemas bundle (schemas.zip is at the repo root, not in config/).
# Strip macOS junk so only a clean schemas/ tree is copied into the runtime image.
COPY schemas.zip .
RUN apt-get update && apt-get install -y --no-install-recommends unzip \
    && unzip -q schemas.zip -d /workspace/schemas_extracted \
    && rm -rf /workspace/schemas_extracted/__MACOSX \
    && find /workspace/schemas_extracted -name '.DS_Store' -delete

# ---------- Runtime image ----------
FROM cgr.dev/chainguard/wolfi-base:latest
WORKDIR /app

# Server binary + compiled plugins
COPY --from=builder /workspace/app/server .
COPY --from=builder /workspace/app/plugins ./plugins

# Config (adapter.yaml, routing files, opa-network-policies.yaml) -> /app/config/onix/
COPY config/ ./config/

# Extracted JSON schemas -> /app/config/onix/schemas  (schemaDir in adapter.yaml)
COPY --from=builder /workspace/schemas_extracted/schemas ./config/onix/schemas

# Example OPA policy at the exact path opa-network-policies.yaml references.
# NOTE: example policy only -- replace with your real network policy for production.
COPY pkg/plugin/implementation/opapolicychecker/testdata/example.rego \
     /app/pkg/plugin/implementation/opapolicychecker/testdata/example.rego

# Matches http.port in config/onix/adapter.yaml
EXPOSE 8080

CMD ["sh", "-c", "./server --config=${CONFIG_FILE}"]
