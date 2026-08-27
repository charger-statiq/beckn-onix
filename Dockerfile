FROM golang:1.26.1-bookworm AS builder

WORKDIR /workspace/app

# Specifically copy only the necessary files and directories
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

# Make the build script executable and run it to build plugins. The version
# ARGs are passed through as environment variables so the otelsetup plugin
# (a separate .so, a separate link unit from the server binary above) gets
# the same build identity instead of falling back to pkg/version's
# "dev"/"unknown" defaults.
RUN chmod +x install/build-plugins.sh && \
    ONIX_VERSION="${ONIX_VERSION}" GIT_COMMIT="${GIT_COMMIT}" GIT_TREE_STATE="${GIT_TREE_STATE}" BUILD_DATE="${BUILD_DATE}" \
    ./install/build-plugins.sh

# Create minimal runtime image
FROM cgr.dev/chainguard/wolfi-base:latest
WORKDIR /app

# Copy binary and plugins built with same Go version
COPY --from=builder /workspace/app/server .
COPY --from=builder /workspace/app/plugins ./plugins

# ---- ADDED: bake the config into the image so CONFIG_FILE resolves ----
# Without this the server crash-loops: it starts with `./server --config=${CONFIG_FILE}`
# and that file must physically exist in the container.
# This puts your config at /app/config/onix/adapter.yaml
# (matches the CONFIG_FILE value in the k8s Secret).
COPY config/ ./config/
# ----------------------------------------------------------------------

# CHANGED: 8081 -> 8080 to match http.port in config/onix/adapter.yaml
EXPOSE 8080

CMD ["sh", "-c", "./server --config=${CONFIG_FILE}"]
