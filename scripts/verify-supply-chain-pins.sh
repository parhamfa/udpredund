#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
checked=0

while IFS= read -r -d '' dockerfile; do
  syntax_line=$(sed -n '1p' "$dockerfile")
  if [[ ! "$syntax_line" =~ ^#\ syntax=docker/dockerfile:[0-9.]+@sha256:[0-9a-f]{64}$ ]]; then
    printf '%s must pin its Dockerfile frontend by sha256 digest\n' "${dockerfile#"$repo_root/"}" >&2
    exit 1
  fi
  checked=$((checked + 1))
done < <(find "$repo_root/container" -type f -name 'Dockerfile*' -print0)

if ((checked == 0)); then
  printf 'no container Dockerfiles were found\n' >&2
  exit 1
fi

printf 'Supply-chain pin checks passed for %d Dockerfiles\n' "$checked"
