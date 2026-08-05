#!/usr/bin/env bash
set -Eeuo pipefail

readonly program="udpredund-entrypoint"
children=()

log() {
  printf '%s: %s\n' "$program" "$*" >&2
}

required() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    log "missing required environment variable: $name"
    exit 64
  fi
}

validate_pt_key() {
  required PT_KEY
  if [[ ! "$PT_KEY" =~ ^[0-9]+$ || "${#PT_KEY}" -gt 10 ]]; then
    log "PT_KEY must be a decimal integer from 1 through 2147483647"
    exit 64
  fi
  local numeric_key=$((10#$PT_KEY))
  if ((numeric_key < 1 || numeric_key > 2147483647)); then
    log "PT_KEY must be a decimal integer from 1 through 2147483647"
    exit 64
  fi
}

stop_children() {
  local pid
  for pid in "${children[@]:-}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in "${children[@]:-}"; do
    wait "$pid" 2>/dev/null || true
  done
}

on_signal() {
  trap - INT TERM
  stop_children
  exit 143
}

trap on_signal INT TERM

run_pair() {
  local pid
  local status
  while :; do
    for pid in "${children[@]}"; do
      if ! kill -0 "$pid" 2>/dev/null; then
        set +e
        wait "$pid"
        status=$?
        set -e
        stop_children
        return "$status"
      fi
    done
    sleep 0.1
  done
}

start_udr_client() {
  udpredund \
    -mode client \
    -listen ":${UDR_LISTEN_PORT}" \
    -next "127.0.0.1:${PT_LISTEN_PORT}" \
    -copies "${COPIES:-2}" \
    -max-duplicate-size "${MAX_DUPLICATE_SIZE:-300}" \
    -gap "${COPY_GAP:-10ms}" &
  children+=("$!")
}

start_pt_client() {
  pingtunnel \
    -type client \
    -l ":${PT_LISTEN_PORT}" \
    -s "$PT_SERVER" \
    -t "$PT_TARGET" \
    -key "$PT_KEY" \
    -loglevel "${PT_LOGLEVEL:-error}" \
    -nolog 1 &
  children+=("$!")
}

readonly role="${ROLE:-}"
case "$role" in
  pt-client)
    required PT_SERVER
    required PT_TARGET
    validate_pt_key
    required PT_LISTEN_PORT
    required UDR_LISTEN_PORT
    log "starting PingTunnel client and UDR1 redundancy client"
    start_pt_client
    start_udr_client
    run_pair
    ;;
  pt-server)
    validate_pt_key
    log "starting PingTunnel server"
    exec pingtunnel \
      -type server \
      -key "$PT_KEY" \
      -loglevel "${PT_LOGLEVEL:-error}" \
      -nolog 1
    ;;
  udr-server)
    required UDR_LISTEN_PORT
    required UDR_NEXT
    log "starting UDR1 redundancy server"
    exec udpredund \
      -mode server \
      -listen ":${UDR_LISTEN_PORT}" \
      -next "$UDR_NEXT" \
      -copies "${COPIES:-2}" \
      -max-duplicate-size "${MAX_DUPLICATE_SIZE:-300}" \
      -gap "${COPY_GAP:-10ms}"
    ;;
  verify)
    test -x /usr/local/bin/pingtunnel
    test -x /usr/local/bin/udpredund
    pingtunnel -h >/dev/null 2>&1 || true
    udpredund -version
    printf 'udpredund image verification passed\n'
    ;;
  *)
    log "ROLE must be pt-client, pt-server, udr-server, or verify"
    exit 64
    ;;
esac
