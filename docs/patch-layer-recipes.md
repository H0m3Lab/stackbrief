# Patch layer recipes

## Recompile a bundled Go helper with a current Go
Example: Uptime Kuma ships `extra/healthcheck` (Go) plus its source `extra/healthcheck.go`.

```dockerfile
ARG BASE
ARG GO_IMAGE=golang:1.27.4-bookworm
FROM ${BASE} AS upstream
FROM ${GO_IMAGE} AS hc
COPY --from=upstream /app/extra/healthcheck.go /src/healthcheck.go
RUN cd /src && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o healthcheck healthcheck.go
FROM upstream
ARG BASE
USER root
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && rm -f /usr/bin/cloudflared            # unused here (no Cloudflare tunnel configured)
COPY --from=hc --chmod=755 /src/healthcheck /app/extra/healthcheck
LABEL stackbrief.upstream="${BASE}"
```

## Remove tools the app never uses at runtime
Node images bundle `npm`, which carries its own dependencies (and their CVEs). If the container
starts with `node app.js`, npm isn't needed at runtime:

```dockerfile
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
```

## Rebuild an upstream Go program from its release tag
When a project's last release was compiled with an old Go, build the same tag with a current one:

```dockerfile
FROM golang:1.27.4-bookworm AS build
ARG VERSION=v0.0.38
RUN git clone --depth 1 --branch ${VERSION} https://github.com/<org>/<project>.git /src
WORKDIR /src
RUN go vet ./... && CGO_ENABLED=0 go build -trimpath -o /out/app .
```
