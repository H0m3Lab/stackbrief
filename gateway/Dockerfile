# Stackbrief gateway: Claude Code (headless) behind a small internal HTTP API.
FROM node:22-slim
ARG CLAUDE_CODE_VERSION=2.1.328
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git ripgrep tini \
 && rm -rf /var/lib/apt/lists/*
# npm/npx/corepack are only needed for this install; removing them drops their CVEs
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} && npm cache clean --force \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack /root/.npm \
 && mkdir -p /data/workspace/memory /data/history /data/home && chown -R node:node /data
WORKDIR /app
COPY server.js /app/server.js
COPY seed /app/seed
USER node
ENV HOME=/data/home USE_BUILTIN_RIPGREP=0 DISABLE_AUTOUPDATER=1
EXPOSE 8765
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "/app/server.js"]
