#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly source_root
test_root="$(mktemp -d)"
readonly test_root
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin"

make_stub() {
  local name="$1"
  local path="$test_root/bin/$name"
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0 $*" >>"%s"\nif [[ "${STUB_BLOCK:-0}" == "1" ]]; then trap "exit 0" TERM INT; while :; do sleep 0.05; done; fi\n' \
    "$test_root/calls" >"$path"
  chmod 0755 "$path"
}

make_stub pingtunnel
make_stub udpredund

export PATH="$test_root/bin:$PATH"
export PT_SERVER="192.0.2.10"
export PT_TARGET="10.254.242.3:46111"
export PT_KEY="1732050807"
export PT_LISTEN_PORT="45111"
export UDR_LISTEN_PORT="44111"
export UDR_NEXT="10.254.242.1:51820"
export COPIES="2"
export MAX_DUPLICATE_SIZE="300"
export COPY_GAP="10ms"

ROLE=pt-server bash "$source_root/container/entrypoint.sh"
ROLE=udr-server bash "$source_root/container/entrypoint.sh"

grep -F -- '-type server -key 1732050807' "$test_root/calls" >/dev/null
grep -F -- '-mode server -listen :44111 -next 10.254.242.1:51820 -copies 2 -max-duplicate-size 300 -gap 10ms' "$test_root/calls" >/dev/null

if ROLE=unknown bash "$source_root/container/entrypoint.sh" 2>/dev/null; then
  printf 'unknown role unexpectedly succeeded\n' >&2
  exit 1
fi

: >"$test_root/calls"
export STUB_BLOCK=1
ROLE=pt-client bash "$source_root/container/entrypoint.sh" &
entrypoint_pid=$!
sleep 0.2
kill -TERM "$entrypoint_pid" 2>/dev/null || true
wait "$entrypoint_pid" 2>/dev/null || true

grep -F -- '-type client -l :45111 -s 192.0.2.10 -t 10.254.242.3:46111 -key 1732050807' "$test_root/calls" >/dev/null
grep -F -- '-mode client -listen :44111 -next 127.0.0.1:45111 -copies 2 -max-duplicate-size 300 -gap 10ms' "$test_root/calls" >/dev/null

printf 'entrypoint tests passed\n'
