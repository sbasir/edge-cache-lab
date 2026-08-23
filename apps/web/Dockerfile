# Base image with Node for building
FROM node:24-slim AS base

ENV PNPM_HOME="/pnpm/store"
ENV PATH="$PNPM_HOME:$PATH"

RUN corepack enable && corepack prepare pnpm@10.28.1 --activate

WORKDIR /usr/src/app

# ------------------------------
# Build stage
FROM base AS build

WORKDIR /usr/src/app

# Copy package files
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

# Copy source files
COPY . .

# Build Vite app
RUN pnpm run build

# ------------------------------
# Runtime stage (nginx serving static files)
FROM nginx:1.30-alpine-slim AS web

# Copy built static assets
COPY --from=build /usr/src/app/dist /usr/share/nginx/html

# Copy custom nginx config for SPA routing
COPY conf/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
