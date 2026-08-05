# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.25.3

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS pingtunnel-builder

ARG TARGETOS
ARG TARGETARCH
ARG PINGTUNNEL_COMMIT=a0d08ec7d44f4829c543416542ef3734453a4a55
ARG PINGTUNNEL_ARCHIVE_SHA256=5b36a5a8be2aad56f370bc442e5f41bbef952eec17ee33fd5c402d439ea32b43

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN mkdir pingtunnel \
    && curl --fail --location --retry 4 --silent --show-error \
        "https://codeload.github.com/esrrhs/pingtunnel/tar.gz/${PINGTUNNEL_COMMIT}" \
        --output /tmp/pingtunnel.tar.gz \
    && echo "${PINGTUNNEL_ARCHIVE_SHA256}  /tmp/pingtunnel.tar.gz" > /tmp/pingtunnel.sha256 \
    && sha256sum -c /tmp/pingtunnel.sha256 \
    && tar -xzf /tmp/pingtunnel.tar.gz -C pingtunnel --strip-components=1 \
    && rm /tmp/pingtunnel.tar.gz /tmp/pingtunnel.sha256

WORKDIR /src/pingtunnel
RUN go test ./... \
    && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
        go build -trimpath -ldflags='-s -w' -o /out/pingtunnel ./cmd

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS udpredund-builder

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
ARG REVISION=unknown
ARG BUILD_DATE=unknown

WORKDIR /src/udpredund
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN go test ./... \
    && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
        go build -trimpath \
        -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${REVISION} -X main.date=${BUILD_DATE}" \
        -o /out/udpredund ./cmd/udpredund

FROM debian:bookworm-slim

ARG VERSION=dev
ARG REVISION=unknown
ARG BUILD_DATE=unknown
ARG PINGTUNNEL_COMMIT=a0d08ec7d44f4829c543416542ef3734453a4a55

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=pingtunnel-builder /out/pingtunnel /usr/local/bin/pingtunnel
COPY --from=pingtunnel-builder /src/pingtunnel/LICENSE /usr/share/licenses/pingtunnel/LICENSE
COPY --from=udpredund-builder /out/udpredund /usr/local/bin/udpredund
COPY container/entrypoint.sh /usr/local/bin/udpredund-entrypoint
COPY LICENSE /usr/share/licenses/udpredund/LICENSE

RUN chmod 0755 \
        /usr/local/bin/pingtunnel \
        /usr/local/bin/udpredund \
        /usr/local/bin/udpredund-entrypoint

LABEL org.opencontainers.image.title="udpredund PingTunnel carrier" \
      org.opencontainers.image.description="UDR1 UDP redundancy relay with pinned PingTunnel for authorized networks" \
      org.opencontainers.image.source="https://github.com/parhamfa/udpredund" \
      org.opencontainers.image.url="https://github.com/parhamfa/udpredund" \
      org.opencontainers.image.documentation="https://github.com/parhamfa/udpredund#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.revision=$REVISION \
      org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.pingtunnel.revision=$PINGTUNNEL_COMMIT

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/udpredund-entrypoint"]
CMD []
STOPSIGNAL SIGTERM
