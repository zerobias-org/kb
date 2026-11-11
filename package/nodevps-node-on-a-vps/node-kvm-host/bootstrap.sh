#!/usr/bin/env bash
# Run the host/NN-*.sh steps in order. Every step is idempotent — re-run freely.
#
#   ./bootstrap.sh            # all steps
#   ./bootstrap.sh 20 50      # only steps whose number prefix matches
#   ./bootstrap.sh --list     # show steps
set -euo pipefail
cd "$(dirname "$0")"

mapfile -t STEPS < <(ls host/[0-9][0-9]-*.sh | sort)

if [ "${1:-}" = "--list" ]; then
  printf '%s\n' "${STEPS[@]}"; exit 0
fi

for step in "${STEPS[@]}"; do
  num="$(basename "$step" | cut -c1-2)"
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$num"; then
    continue
  fi
  printf '\n\e[1m==> %s\e[0m\n' "$step"
  "./$step"
done
printf '\n\e[1;32mbootstrap complete\e[0m\n'
