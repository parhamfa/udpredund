#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_root
version="${VERSION:?set VERSION, for example v0.1.0-beta.1}"
output_dir="${OUTPUT_DIR:-$source_root/dist}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

bundle="$work_dir/udpredund-$version-routeros-templates"
mkdir -p "$bundle" "$output_dir"
install -m 0644 "$source_root/deploy/routeros/"*.rsc "$bundle/"
install -m 0644 "$source_root/LICENSE" "$bundle/LICENSE"
install -m 0644 "$source_root/THIRD_PARTY_NOTICES" "$bundle/THIRD_PARTY_NOTICES"
mkdir -p "$bundle/licenses/pingtunnel"
install -m 0644 "$source_root/third_party/pingtunnel/LICENSE" "$bundle/licenses/pingtunnel/LICENSE"
tar -C "$work_dir" -czf "$output_dir/udpredund-$version-routeros-templates.tar.gz" "$(basename "$bundle")"
printf 'Created %s\n' "$output_dir/udpredund-$version-routeros-templates.tar.gz"
