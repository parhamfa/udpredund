#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_root
version="${VERSION:?set VERSION, for example v0.1.0-beta.1}"
architecture="${ARCH:?set ARCH to amd64 or arm64}"
binary_dir="${BINARY_DIR:-$source_root/dist}"
output_dir="${OUTPUT_DIR:-$source_root/dist}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*$ ]]; then
  printf 'invalid prerelease version: %s\n' "$version" >&2
  exit 64
fi

case "$architecture" in
  amd64|arm64) ;;
  *) printf 'unsupported architecture: %s\n' "$architecture" >&2; exit 64 ;;
esac

bundle="$work_dir/udpredund-$version-ubuntu-$architecture"
mkdir -p "$bundle/bin" "$bundle/systemd" "$output_dir"
install -m 0755 "$binary_dir/udpredund-linux-$architecture" "$bundle/bin/udpredund"
install -m 0755 "$binary_dir/pingtunnel-linux-$architecture" "$bundle/bin/pingtunnel"
install -m 0755 "$source_root/deploy/ubuntu/install.sh" "$bundle/install.sh"
install -m 0755 "$source_root/deploy/ubuntu/uninstall.sh" "$bundle/uninstall.sh"
install -m 0644 "$source_root/deploy/ubuntu/systemd/udpredund-pingtunnel.service" "$bundle/systemd/udpredund-pingtunnel.service"
install -m 0644 "$source_root/deploy/ubuntu/systemd/udpredund-relay.service" "$bundle/systemd/udpredund-relay.service"
install -m 0644 "$source_root/LICENSE" "$bundle/LICENSE"
install -m 0644 "$source_root/THIRD_PARTY_NOTICES" "$bundle/THIRD_PARTY_NOTICES"
mkdir -p "$bundle/licenses/pingtunnel"
install -m 0644 "$source_root/third_party/pingtunnel/LICENSE" "$bundle/licenses/pingtunnel/LICENSE"

tar -C "$work_dir" -czf "$output_dir/udpredund-$version-ubuntu-$architecture.tar.gz" "$(basename "$bundle")"
printf 'Created %s\n' "$output_dir/udpredund-$version-ubuntu-$architecture.tar.gz"
