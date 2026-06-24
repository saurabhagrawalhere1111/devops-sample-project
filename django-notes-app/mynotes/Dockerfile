# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# NotesOps frontend image: build the React SPA, serve it with nginx,
# and reverse-proxy API/admin/metrics traffic to the backend service.
# ---------------------------------------------------------------------------

# --- Stage 1: build the React app -------------------------------------------
FROM node:20-alpine AS build

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# --- Stage 2: nginx runtime -------------------------------------------------
FROM nginx:1.27-alpine AS runtime

# nginx config that serves the SPA and proxies /api -> backend.
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
    CMD wget -qO- http://localhost/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
