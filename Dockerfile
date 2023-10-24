# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.18 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG VERSION
ADD https://github.com/autobrr/autobrr.git#v$VERSION ./

# frontend stage ===============================================================
FROM base AS build-frontend

# build dependencies
RUN apk add --no-cache build-base python3 nodejs-current && corepack enable

# node_modules
COPY --from=source /src/web/package.json /src/web/pnpm-lock.yaml /src/web/tsconfig.json ./
RUN pnpm install --frozen-lockfile

# frontend source and build
COPY --from=source /src/web ./
RUN pnpm build

# build stage ==================================================================
FROM base AS build-backend
ENV CGO_ENABLED=0

# dependencies
RUN apk add --no-cache build-base go git

# build dependencies
COPY --from=source /src/go.mod /src/go.sum ./
RUN go mod download

# build app
COPY --from=source /src/web/build.go ./web/
COPY --from=source /src/cmd ./cmd
COPY --from=source /src/pkg ./pkg
COPY --from=source /src/internal ./internal
COPY --from=build-frontend /src/dist ./web/dist
ARG VERSION
RUN mkdir /build && \
    go build \
        -ldflags "-s -w -X main.version=$VERSION -X main.date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        -o /build/ ./cmd/...

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
WORKDIR /config
VOLUME /config
EXPOSE 7474

# runtime dependencies
RUN apk add --no-cache tzdata s6-overlay curl

# copy files
COPY --from=build-backend /build /app
COPY ./rootfs/. /

# run using s6-overlay
ENTRYPOINT ["/entrypoint.sh"]
