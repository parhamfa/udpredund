#!/usr/bin/env bash
set -Eeuo pipefail

program="udpredund-install"
bundle_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
destdir="${DESTDIR:-}"
non_interactive=0
skip_start="${UDPR_INSTALL_SKIP_START:-0}"

usage() {
  printf 'Usage: %s [--non-interactive] [--skip-start]\n' "$program"
  printf 'Non-interactive mode reads UDPR_INSTALL_PT_KEY and optional UDPR_INSTALL_* settings from the environment.\n'
}

while (($# > 0)); do
  case "$1" in
    --non-interactive) non_interactive=1 ;;
    --skip-start) skip_start=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$program" "$1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

if [[ -z "$destdir" && "$EUID" -ne 0 ]]; then
  printf '%s: run as root\n' "$program" >&2
  exit 77
fi

for command in install cp date mktemp; do
  command -v "$command" >/dev/null || {
    printf '%s: required command not found: %s\n' "$program" "$command" >&2
    exit 69
  }
done
if [[ ! -x "$bundle_root/bin/udpredund" || ! -x "$bundle_root/bin/pingtunnel" ]]; then
  printf '%s: bundle is missing executable binaries under bin/\n' "$program" >&2
  exit 66
fi

prompt_value() {
  local variable_name="$1"
  local prompt="$2"
  local default_value="$3"
  local value=""
  read -r -p "$prompt [$default_value]: " value
  printf -v "$variable_name" '%s' "${value:-$default_value}"
}

if ((non_interactive)); then
  pt_key="${UDPR_INSTALL_PT_KEY:-}"
  wg_port="${UDPR_INSTALL_WG_PORT:-51820}"
  udr_port="${UDPR_INSTALL_UDR_PORT:-46111}"
  copies="${UDPR_INSTALL_COPIES:-2}"
  max_duplicate_size="${UDPR_INSTALL_MAX_DUPLICATE_SIZE:-300}"
  copy_gap="${UDPR_INSTALL_COPY_GAP:-10ms}"
else
  if [[ ! -t 0 ]]; then
    printf '%s: interactive mode requires a terminal; use --non-interactive with environment variables\n' "$program" >&2
    exit 64
  fi
  read -r -s -p 'PingTunnel key (input hidden): ' pt_key
  printf '\n'
  prompt_value wg_port 'Existing WireGuard listen port on this Ubuntu exit' '51820'
  prompt_value udr_port 'Loopback UDR1 listen port' '46111'
  prompt_value copies 'Copies for eligible payloads' '2'
  prompt_value max_duplicate_size 'Maximum duplicated payload size in bytes' '300'
  prompt_value copy_gap 'Delay between copies' '10ms'
fi

if [[ ! "$pt_key" =~ ^[0-9]+$ || "${#pt_key}" -gt 10 ]]; then
  printf '%s: PingTunnel key must be a decimal integer from 1 through 2147483647\n' "$program" >&2
  exit 64
fi
pt_key_number=$((10#$pt_key))
if ((pt_key_number < 1 || pt_key_number > 2147483647)); then
  printf '%s: PingTunnel key must be a decimal integer from 1 through 2147483647\n' "$program" >&2
  exit 64
fi
validate_port() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || ((value < 1 || value > 65535)); then
    printf '%s: %s must be an integer from 1 through 65535\n' "$program" "$name" >&2
    exit 64
  fi
}
validate_port "WireGuard port" "$wg_port"
validate_port "UDR1 port" "$udr_port"
if [[ ! "$copies" =~ ^[1-8]$ ]]; then
  printf '%s: copies must be from 1 through 8\n' "$program" >&2
  exit 64
fi
if [[ ! "$max_duplicate_size" =~ ^[0-9]+$ ]] || ((max_duplicate_size > 65495)); then
  printf '%s: max duplicate size must be from 0 through 65495\n' "$program" >&2
  exit 64
fi
if [[ ! "$copy_gap" =~ ^([0-9]+([.][0-9]+)?(ns|us|ms|s|m|h))+$ && "$copy_gap" != "0" ]]; then
  printf '%s: copy gap must be a Go duration such as 10ms\n' "$program" >&2
  exit 64
fi

prefix_path() {
  printf '%s%s' "$destdir" "$1"
}

binary_dir="$(prefix_path /usr/local/libexec/udpredund)"
config_dir="$(prefix_path /etc/udpredund)"
unit_dir="$(prefix_path /etc/systemd/system)"
state_dir="$(prefix_path /var/lib/udpredund)"
backup_dir="$state_dir/backups/$(date -u +%Y%m%dT%H%M%SZ)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
umask 077

managed_paths=(
  "$binary_dir/udpredund"
  "$binary_dir/pingtunnel"
  "$config_dir/udpredund.env"
  "$unit_dir/udpredund-pingtunnel.service"
  "$unit_dir/udpredund-relay.service"
)
has_existing=0
for path in "${managed_paths[@]}"; do
  if [[ -e "$path" ]]; then
    has_existing=1
    break
  fi
done
if ((has_existing)); then
  install -d -m 0700 "$backup_dir"
  for path in "${managed_paths[@]}"; do
    if [[ -e "$path" ]]; then
      cp -a "$path" "$backup_dir/"
    fi
  done
  printf '%s: existing managed files backed up under %s\n' "$program" "$backup_dir"
fi

env_file="$temporary_dir/udpredund.env"
{
  printf 'PT_KEY="%s"\n' "$pt_key"
  printf 'PT_LOGLEVEL="error"\n'
  printf 'UDR_LISTEN="127.0.0.1:%s"\n' "$udr_port"
  printf 'UDR_NEXT="127.0.0.1:%s"\n' "$wg_port"
  printf 'COPIES="%s"\n' "$copies"
  printf 'MAX_DUPLICATE_SIZE="%s"\n' "$max_duplicate_size"
  printf 'COPY_GAP="%s"\n' "$copy_gap"
} >"$env_file"
chmod 0600 "$env_file"

install -d -m 0755 "$binary_dir" "$unit_dir"
install -d -m 0700 "$config_dir" "$state_dir"
install -m 0755 "$bundle_root/bin/udpredund" "$binary_dir/udpredund"
install -m 0755 "$bundle_root/bin/pingtunnel" "$binary_dir/pingtunnel"
install -m 0600 "$env_file" "$config_dir/udpredund.env"
install -m 0644 "$bundle_root/systemd/udpredund-pingtunnel.service" "$unit_dir/udpredund-pingtunnel.service"
install -m 0644 "$bundle_root/systemd/udpredund-relay.service" "$unit_dir/udpredund-relay.service"

if command -v systemd-analyze >/dev/null; then
  if [[ -n "$destdir" ]]; then
    systemd-analyze verify --root="$destdir" /etc/systemd/system/udpredund-pingtunnel.service /etc/systemd/system/udpredund-relay.service
  else
    systemd-analyze verify "$unit_dir/udpredund-pingtunnel.service" "$unit_dir/udpredund-relay.service"
  fi
else
  printf '%s: systemd-analyze is required to verify units\n' "$program" >&2
  exit 69
fi

if [[ "$skip_start" != "1" ]]; then
  systemctl daemon-reload
  systemctl enable --now udpredund-pingtunnel.service udpredund-relay.service
  for unit in udpredund-pingtunnel.service udpredund-relay.service; do
    if ! systemctl --quiet is-active "$unit"; then
      printf '%s: %s did not become active; inspect it with journalctl -u %s\n' "$program" "$unit" "$unit" >&2
      exit 1
    fi
  done
fi

printf '%s: installation complete\n' "$program"
printf 'No firewall or WireGuard setting was changed.\n'
printf 'Set the RouterOS entry PT_TARGET to 127.0.0.1:%s.\n' "$udr_port"
printf 'The tested starting profile is copies=%s max-duplicate-size=%s gap=%s; tune only with measurements.\n' "$copies" "$max_duplicate_size" "$copy_gap"
