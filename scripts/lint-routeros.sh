#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_root
routeros_dir="$source_root/deploy/routeros"

fail() {
  printf 'RouterOS template check failed: %s\n' "$*" >&2
  exit 1
}

if grep -En '^[[:space:]]*/(ip/route|routing|interface/wireguard)(/|[[:space:]])' "$routeros_dir"/install-*.rsc; then
  fail "installer contains a direct route or WireGuard mutation"
fi
if grep -Ein '(private-key|public-key|persistent-keepalive|(^|[^-])mtu=|distance=|0[.]0[.]0[.]0/0)' "$routeros_dir"/*.rsc; then
  fail "template contains a forbidden WireGuard, MTU, distance, or default-route setting"
fi
grep -F ':local allowUnrestrictedICMP false' "$routeros_dir/install-exit.rsc" >/dev/null || fail "exit must fail closed"
# shellcheck disable=SC2016
grep -F 'src-address=$entrySourceCIDR' "$routeros_dir/install-exit.rsc" >/dev/null || fail "exit DNAT must support source restriction"
grep -F 'start-on-boot=no' "$routeros_dir/install-entry.rsc" >/dev/null || fail "entry must start disabled"
grep -F 'start-on-boot=no' "$routeros_dir/install-exit.rsc" >/dev/null || fail "exit must start disabled"
if grep -F 'logging=yes' "$routeros_dir"/*.rsc; then
  fail "RouterOS container logging may disclose environment values"
fi
if grep -E '/log/print|/log print' "$routeros_dir"/*.rsc; then
  fail "verification and uninstall templates must not print container logs"
fi
grep -F 'WireGuard peer still targets this carrier' "$routeros_dir/uninstall-entry.rsc" >/dev/null || fail "entry uninstall must protect active peer endpoints"
grep -F 'No WireGuard setting was changed' "$routeros_dir/install-entry.rsc" >/dev/null || fail "entry must disclose manual endpoint handoff"

printf 'RouterOS static safety checks passed\n'
