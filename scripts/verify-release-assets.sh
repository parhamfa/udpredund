#!/usr/bin/env bash
set -Eeuo pipefail

version="${1:?usage: verify-release-assets.sh VERSION ASSET_DIR}"
asset_dir="${2:?usage: verify-release-assets.sh VERSION ASSET_DIR}"

case "$version" in
  v[0-9]*.[0-9]*.[0-9]*-*) ;;
  *) printf 'invalid prerelease version: %s\n' "$version" >&2; exit 64 ;;
esac
[[ -d "$asset_dir" ]] || { printf 'asset directory not found: %s\n' "$asset_dir" >&2; exit 66; }

required=(
  SHA256SUMS
  LICENSE
  THIRD_PARTY_NOTICES
  pingtunnel-LICENSE
  "udpredund-linux-amd64"
  "udpredund-linux-arm64"
  "udpredund-pingtunnel-$version-routeros-amd64.tar"
  "udpredund-pingtunnel-$version-routeros-arm64.tar"
  "udpredund-$version-routeros-templates.tar.gz"
  "udpredund-$version-ubuntu-amd64.tar.gz"
  "udpredund-$version-ubuntu-arm64.tar.gz"
  "udpredund-$version-source.spdx.json"
  "udpredund-pingtunnel-$version-routeros-amd64.spdx.json"
  "udpredund-pingtunnel-$version-routeros-arm64.spdx.json"
)
for name in "${required[@]}"; do
  [[ -f "$asset_dir/$name" ]] || { printf 'missing release asset: %s\n' "$name" >&2; exit 1; }
done

(cd "$asset_dir" && sha256sum -c SHA256SUMS)

file "$asset_dir/udpredund-linux-amd64" | grep -Eq 'ELF 64-bit.*(x86-64|x86_64)'
file "$asset_dir/udpredund-linux-arm64" | grep -Eq 'ELF 64-bit.*(ARM aarch64|aarch64)'

for architecture in amd64 arm64; do
  image_tar="$asset_dir/udpredund-pingtunnel-$version-routeros-$architecture.tar"
  tar -tf "$image_tar" | grep -Fx 'manifest.json' >/dev/null
  jq -e '.spdxVersion | startswith("SPDX-")' \
    "$asset_dir/udpredund-pingtunnel-$version-routeros-$architecture.spdx.json" >/dev/null

  ubuntu_bundle="$asset_dir/udpredund-$version-ubuntu-$architecture.tar.gz"
  tar -tzf "$ubuntu_bundle" | grep -E '/bin/udpredund$' >/dev/null
  tar -tzf "$ubuntu_bundle" | grep -E '/bin/pingtunnel$' >/dev/null
  tar -tzf "$ubuntu_bundle" | grep -E '/systemd/udpredund-pingtunnel[.]service$' >/dev/null
  tar -tzf "$ubuntu_bundle" | grep -E '/install[.]sh$' >/dev/null
  tar -tzf "$ubuntu_bundle" | grep -E '/uninstall[.]sh$' >/dev/null
done

templates="$asset_dir/udpredund-$version-routeros-templates.tar.gz"
for template in install-entry.rsc install-exit.rsc verify.rsc uninstall-entry.rsc uninstall-exit.rsc; do
  tar -tzf "$templates" | grep -E "/$template$" >/dev/null
done
jq -e '.spdxVersion | startswith("SPDX-")' "$asset_dir/udpredund-$version-source.spdx.json" >/dev/null

if find "$asset_dir" -maxdepth 1 -type f -iname '*latest*' | grep -q .; then
  printf 'beta release must not contain a latest artifact\n' >&2
  exit 1
fi

printf 'Release assets and checksums verified for %s\n' "$version"
