# syntax=docker/dockerfile:1.7
FROM --platform=$BUILDPLATFORM golang:1.25.3-bookworm AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod ./
COPY container/tests/udp-tool ./container/tests/udp-tool
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -buildvcs=false -ldflags='-s -w' -o /out/udp-tool ./container/tests/udp-tool

FROM scratch
COPY --from=builder /out/udp-tool /udp-tool
ENTRYPOINT ["/udp-tool"]
