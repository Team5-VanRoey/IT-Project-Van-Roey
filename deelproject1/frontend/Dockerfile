# Frontend image: build with Node, serve with unprivileged nginx.
# Built ONCE per frontend source version by CI (scripts/014_images.sh); the same image runs in
# every environment. The React build uses relative URLs (/api), so nothing environment-specific
# is baked in; the API address is set at runtime with API_UPSTREAM.
# nginx also forwards /api and /health to the backend (API_UPSTREAM), so the browser only
# talks to one origin and no CORS configuration is needed.
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.29-alpine
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
# Default for Docker Compose; Azure sets it to the API container app (scripts/015_setup_azure.sh)
ENV API_UPSTREAM=http://api:8080
# Shown on /version; the deployment sets the real values (nothing environment-specific is built in)
ENV DEPLOY_ENV=unknown DEPLOY_COMMIT=unknown API_VERSION=unknown WEB_VERSION=unknown
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=5 CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
