#!/usr/bin/env bash
set -Eeuo pipefail

readonly pingtunnel_commit="a0d08ec7d44f4829c543416542ef3734453a4a55"
readonly pingtunnel_archive_sha256="5b36a5a8be2aad56f370bc442e5f41bbef952eec17ee33fd5c402d439ea32b43"
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_root

version="${VERSION:-dev}"
revision="${REVISION:-$(git -C "$source_root" rev-parse HEAD 2>/dev/null || printf unknown)}"
build_date="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
output_dir="${OUTPUT_DIR:-$source_root/dist}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

for command in curl go sha256sum tar; do
  command -v "$command" >/dev/null || {
    printf 'required command not found: %s\n' "$command" >&2
    exit 69
  }
done

mkdir -p "$output_dir" "$work_dir/pingtunnel"
curl --fail --location --retry 4 --silent --show-error \
  "https://codeload.github.com/esrrhs/pingtunnel/tar.gz/${pingtunnel_commit}" \
  --output "$work_dir/pingtunnel.tar.gz"
printf '%s  %s\n' "$pingtunnel_archive_sha256" "$work_dir/pingtunnel.tar.gz" >"$work_dir/pingtunnel.sha256"
sha256sum -c "$work_dir/pingtunnel.sha256"
tar -xzf "$work_dir/pingtunnel.tar.gz" -C "$work_dir/pingtunnel" --strip-components=1

(cd "$source_root" && go test ./...)
(cd "$work_dir/pingtunnel" && go test ./...)

for architecture in amd64 arm64; do
  CGO_ENABLED=0 GOOS=linux GOARCH="$architecture" \
    go build -trimpath -buildvcs=false \
    -ldflags="-s -w -buildid= -X main.version=${version} -X main.commit=${revision} -X main.date=${build_date}" \
    -o "$output_dir/udpredund-linux-$architecture" "$source_root/cmd/udpredund"
  (
    cd "$work_dir/pingtunnel"
    CGO_ENABLED=0 GOOS=linux GOARCH="$architecture" \
      go build -trimpath -buildvcs=false -ldflags='-s -w -buildid=' \
      -o "$output_dir/pingtunnel-linux-$architecture" ./cmd
  )
done

printf 'Built Linux amd64 and arm64 binaries under %s\n' "$output_dir"
