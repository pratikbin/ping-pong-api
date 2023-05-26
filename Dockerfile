# syntax=docker/dockerfile:1
ARG NODE_VERSION=18
FROM node:${NODE_VERSION} AS build
WORKDIR /app
COPY . .
RUN --mount=type=cache,target=/root/.npm \
  npm install

FROM cgr.dev/chainguard/node:${NODE_VERSION}
COPY --from=build /app /app
WORKDIR /app
CMD ["server.js"]
