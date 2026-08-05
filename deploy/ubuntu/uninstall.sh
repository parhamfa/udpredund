#!/usr/bin/env bash
set -Eeuo pipefail

program="udpredund-uninstall"
destdir="${DESTDIR:-}"
assume_yes=0
keep_config=0
skip_stop="${UDPR_INSTALL_SKIP_START:-0}"

usage() {
  printf 'Usage: %s [--yes] [--keep-config] [--skip-stop]\n' "$program"
}

while (($# > 0)); do
  case "$1" in
    --yes) assume_yes=1 ;;
    --keep-config) keep_config=1 ;;
    --skip-stop) skip_stop=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$program" "$1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

if [[ -z "$destdir" && "$EUID" -ne 0 ]]; then
  printf '%s: run as root\n' "$program" >&2
  exit 77
fi
if ((!assume_yes)); then
  if [[ ! -t 0 ]]; then
    printf '%s: confirmation requires a terminal; pass --yes for unattended removal\n' "$program" >&2
    exit 64
  fi
  read -r -p 'Remove the udpredund Ubuntu services and binaries? [y/N] ' answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || exit 0
fi

prefix_path() {
  printf '%s%s' "$destdir" "$1"
}

binary_dir="$(prefix_path /usr/local/libexec/udpredund)"
config_dir="$(prefix_path /etc/udpredund)"
unit_dir="$(prefix_path /etc/systemd/system)"

if [[ "$skip_stop" != "1" ]]; then
  systemctl disable --now udpredund-pingtunnel.service udpredund-relay.service 2>/dev/null || true
fi
rm -f "$unit_dir/udpredund-pingtunnel.service" "$unit_dir/udpredund-relay.service"
rm -f "$binary_dir/udpredund" "$binary_dir/pingtunnel"
if ((keep_config == 0)); then
  rm -f "$config_dir/udpredund.env"
fi
rmdir "$binary_dir" 2>/dev/null || true
rmdir "$config_dir" 2>/dev/null || true

if [[ "$skip_stop" != "1" ]]; then
  systemctl daemon-reload
  systemctl reset-failed udpredund-pingtunnel.service udpredund-relay.service 2>/dev/null || true
fi

printf '%s: services and binaries removed\n' "$program"
if ((keep_config)); then
  printf 'The root-only environment file was retained under %s.\n' "$config_dir"
fi
printf 'No firewall or WireGuard setting was changed. Backups under /var/lib/udpredund were retained.\n'
