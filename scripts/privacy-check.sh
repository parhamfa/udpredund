#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly source_root
cd "$source_root"

failures=0
fail() {
  printf 'privacy check: %s\n' "$*" >&2
  failures=$((failures + 1))
}

while IFS= read -r path; do
  case "$path" in
    *.pcap|*.pcapng|*.log|*.backup|*.bak|*.tar|*.tar.gz|*.zip|*.key|*.pem|*_ssh.json)
      fail "forbidden tracked artifact: $path"
      ;;
  esac
  case "/$path/" in
    */results/*|*/captures/*|*/artifacts/*|*/backups/*)
      fail "forbidden operational-evidence path: $path"
      ;;
  esac
  if [[ -f "$path" ]]; then
    size=$(wc -c <"$path")
    if ((size > 1048576)); then
      fail "tracked file exceeds 1 MiB: $path"
    fi
    mime=$(file --brief --mime-type "$path")
    case "$mime" in
      text/*|application/json|application/x-shellscript|application/x-empty) ;;
      *) fail "non-text tracked file ($mime): $path" ;;
    esac
  fi
done < <(git ls-files)

if git ls-files -s | grep -Eq '^(120000|160000) '; then
  fail "tracked symlinks or submodules require manual privacy review"
fi

if git grep -nE '(/Users/|/home/[^/[:space:]]+/|BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY)' -- . ':(exclude)scripts/privacy-check.sh'; then
  fail "absolute user path or private-key marker found"
fi

while IFS= read -r ip; do
  [[ -n "$ip" ]] || continue
  IFS=. read -r a b c d <<<"$ip"
  if ((a > 255 || b > 255 || c > 255 || d > 255)); then
    continue
  fi
  case "$ip" in
    0.0.0.0|255.255.255.255|127.*|10.*|192.168.*|192.0.2.*|198.51.100.*|203.0.113.*) continue ;;
  esac
  if ((a == 172 && b >= 16 && b <= 31)); then
    continue
  fi
  fail "non-documentation public IPv4 literal found: $ip"
done < <(git grep -hEo '([0-9]{1,3}[.]){3}[0-9]{1,3}' -- . | sort -u || true)

if ((failures > 0)); then
  exit 1
fi
printf 'Privacy checks passed: tracked files are text-only and contain no non-documentation public IPv4 literals.\n'
