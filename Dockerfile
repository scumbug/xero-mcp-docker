# syntax=docker/dockerfile:1
#
# Xero MCP server (aspiers "best-of-breed" fork) with the self-refreshing
# XERO_TOKEN_FILE auth mode. Upstream source is pinned by tag AND commit SHA;
# the build fails if the tag ever points somewhere else.
#
# To bump upstream: change UPSTREAM_REF and UPSTREAM_SHA below (both stages
# read them from here) and push. The workflow tags the image with UPSTREAM_REF.

ARG UPSTREAM_REPO=https://github.com/aspiers/xero-mcp-server.git
ARG UPSTREAM_REF=best-of-breed-2026-09-23-2
ARG UPSTREAM_SHA=fdc8a94a74871890fa82916fec104bc650a0dfec
# stdio -> Streamable HTTP bridge used by `http` mode.
ARG SUPERGATEWAY_VERSION=4.3.0

# ---------------------------------------------------------------------------
FROM node:26-alpine AS build
ARG UPSTREAM_REPO
ARG UPSTREAM_REF
ARG UPSTREAM_SHA

RUN apk add --no-cache git

WORKDIR /src
RUN git clone --depth 1 --branch "${UPSTREAM_REF}" "${UPSTREAM_REPO}" . \
 && actual="$(git rev-parse HEAD)" \
 && if [ "${actual}" != "${UPSTREAM_SHA}" ]; then \
      echo "Upstream ${UPSTREAM_REF} is ${actual}, expected ${UPSTREAM_SHA}" >&2; exit 1; \
    fi

# --ignore-scripts: the "prepare" hook would build too early; build explicitly.
RUN npm ci --ignore-scripts --no-audit --no-fund \
 && npm run build

# ---------------------------------------------------------------------------
FROM node:26-alpine
ARG UPSTREAM_REPO
ARG UPSTREAM_REF
ARG UPSTREAM_SHA
ARG SUPERGATEWAY_VERSION

LABEL org.opencontainers.image.title="xero-mcp-docker" \
      org.opencontainers.image.description="Xero MCP server (aspiers best-of-breed fork) with self-refreshing OAuth token file" \
      org.opencontainers.image.licenses="MIT" \
      io.github.scumbug.upstream.repo="${UPSTREAM_REPO}" \
      io.github.scumbug.upstream.ref="${UPSTREAM_REF}" \
      io.github.scumbug.upstream.sha="${UPSTREAM_SHA}" \
      io.github.scumbug.supergateway.version="${SUPERGATEWAY_VERSION}"

# tini: forwards signals so containers stop cleanly.
RUN apk add --no-cache tini \
 && npm install -g --no-audit --no-fund "supergateway@${SUPERGATEWAY_VERSION}" \
 && npm cache clean --force

ENV NODE_ENV=production \
    XERO_TOKEN_FILE=/data/tokens.json

WORKDIR /app
COPY --from=build /src/package.json /src/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund \
 && npm cache clean --force
COPY --from=build /src/dist ./dist
COPY --from=build /src/LICENSE ./LICENSE.upstream
COPY --chmod=755 docker-entrypoint.sh ./docker-entrypoint.sh
COPY gateway-config.mjs ./gateway-config.mjs

# The token file, its lock file and temp files all live in /data, so the
# directory itself must be writable by the container user (uid 1000 by default).
RUN mkdir -p /data && chown node:node /data
USER node
VOLUME ["/data"]

# Modes (see docker-entrypoint.sh):
#   stdio (default)  one org over stdin/stdout, run with `docker run -i`
#   http             one Streamable HTTP endpoint per org in XERO_ORGS, on :8000
#   auth             one-time OAuth bootstrap
EXPOSE 8000
ENTRYPOINT ["/sbin/tini", "--", "/app/docker-entrypoint.sh"]
CMD ["stdio"]
