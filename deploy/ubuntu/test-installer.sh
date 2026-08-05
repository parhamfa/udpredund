#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly source_root
test_root="$(mktemp -d)"
readonly test_root
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bundle/bin" "$test_root/bundle/systemd" "$test_root/stubs"
cp "$source_root/deploy/ubuntu/install.sh" "$source_root/deploy/ubuntu/uninstall.sh" "$test_root/bundle/"
cp "$source_root/deploy/ubuntu/systemd/"*.service "$test_root/bundle/systemd/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bundle/bin/udpredund"
printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bundle/bin/pingtunnel"
chmod 0755 "$test_root/bundle/bin/udpredund" "$test_root/bundle/bin/pingtunnel" "$test_root/bundle/"*.sh

printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/stubs/systemd-analyze"
chmod 0755 "$test_root/stubs/systemd-analyze"

export PATH="$test_root/stubs:$PATH"
export DESTDIR="$test_root/root"
export UDPR_INSTALL_SKIP_START=1
export UDPR_INSTALL_PT_KEY='1732050807'

if grep -Eq 'systemctl([[:space:]]+--[^[:space:]]+)*[[:space:]]+status' "$test_root/bundle/install.sh"; then
  printf 'installer must not print systemctl status because PingTunnel argv contains PT_KEY\n' >&2
  exit 1
fi

"$test_root/bundle/install.sh" --non-interactive --skip-start

test -x "$DESTDIR/usr/local/libexec/udpredund/udpredund"
test -x "$DESTDIR/usr/local/libexec/udpredund/pingtunnel"
test "$(stat -f '%Lp' "$DESTDIR/etc/udpredund/udpredund.env" 2>/dev/null || stat -c '%a' "$DESTDIR/etc/udpredund/udpredund.env")" = "600"
grep -F 'PT_KEY="1732050807"' "$DESTDIR/etc/udpredund/udpredund.env" >/dev/null
grep -F 'UDR_NEXT="127.0.0.1:51820"' "$DESTDIR/etc/udpredund/udpredund.env" >/dev/null

"$test_root/bundle/uninstall.sh" --yes --skip-stop
test ! -e "$DESTDIR/usr/local/libexec/udpredund/udpredund"
test ! -e "$DESTDIR/etc/udpredund/udpredund.env"

printf 'Ubuntu installer tests passed\n'
