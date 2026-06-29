FROM node:22-bookworm-slim AS backend-deps
WORKDIR /app/backend
ARG NPM_REGISTRY=https://registry.npmjs.org/
RUN npm config set registry ${NPM_REGISTRY}
COPY backend/package.json backend/package-lock.json ./
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ libsqlite3-dev ca-certificates \
  && npm ci --omit=dev --include=optional --no-audit --no-fund --cache /tmp/npm-cache \
  && rm -rf /tmp/npm-cache \
  && find node_modules -type f \( -name "*.d.ts" -o -name "*.map" -o -name "*.md" -o -name "*.markdown" \) -delete \
  && apt-get purge -y --auto-remove python3 make g++ libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

FROM node:22-bookworm-slim AS frontend-build
WORKDIR /app/frontend
ARG NPM_REGISTRY=https://registry.npmjs.org/
RUN npm config set registry ${NPM_REGISTRY}
COPY frontend/package.json frontend/package-lock.json frontend/.npmrc ./
RUN npm ci --no-audit --no-fund --cache /tmp/npm-cache \
  && rm -rf /tmp/npm-cache
COPY frontend/ ./
ENV VITE_BACKEND_URL=
ENV VITE_IS_DOCKER=true
RUN npm run build

FROM node:22-bookworm-slim
WORKDIR /app
RUN apt-get update \
  && apt-get install -y --no-install-recommends nginx libsqlite3-0 gettext-base ca-certificates \
  && rm -f /etc/nginx/sites-enabled/default \
  && mkdir -p /run/nginx /data /usr/share/nginx/html \
  && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
ENV RUNTIME_ENV=docker
ENV DATA_DIR=/data
ENV BACKEND_PORT=8787
ENV TASK_WORKER_POOL_SIZE=2
ENV SCHEDULED_TICK_CRON="*/1 * * * *"
ENV PORT=7860

COPY --from=backend-deps /app/backend/node_modules ./backend/node_modules
COPY backend/ ./backend/
COPY --from=frontend-build /app/frontend/dist /usr/share/nginx/html
COPY docker/hf/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY docker/hf/start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 7860
CMD ["/app/start.sh"]
