# Build upstream Paperclip from a pinned ref.
FROM node:22-bookworm AS paperclip-build
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=v2026.325.0

WORKDIR /paperclip
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js

# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gosu \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /app
COPY --from=paperclip-build /paperclip /app

WORKDIR /wrapper
COPY package.json /wrapper/package.json
RUN npm install --omit=dev && npm cache clean --force
COPY src /wrapper/src
COPY scripts/entrypoint.sh /wrapper/entrypoint.sh
COPY scripts/bootstrap-ceo.mjs /wrapper/template/bootstrap-ceo.mjs
RUN chmod +x /wrapper/entrypoint.sh

RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai
RUN npm install --global --omit=dev tsx

RUN mv /usr/local/bin/codex /usr/local/bin/codex-real \
 && printf '%s\n' \
'#!/usr/bin/env bash' \
'set -euo pipefail' \
'for arg in "$@"; do' \
'  if [ "$arg" = "--skip-git-repo-check" ]; then' \
'    exec /usr/local/bin/codex-real "$@"' \
'  fi' \
'done' \
'exec /usr/local/bin/codex-real "$@" --skip-git-repo-check' \
> /usr/local/bin/codex \
 && chmod +x /usr/local/bin/codex

RUN mkdir -p /paperclip \
    && chown -R node:node /app /paperclip /wrapper

EXPOSE 3100
ENTRYPOINT ["/wrapper/entrypoint.sh"]
CMD ["node", "/wrapper/src/server.js"]
