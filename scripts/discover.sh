#!/usr/bin/env bash
# Print absolute paths of enabled extension directories (one per line).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

ROOT="$(repo_root)"
EXT_ROOT="${ROOT}/extensions"

[[ -d "$EXT_ROOT" ]] || die "extensions directory missing: $EXT_ROOT"

shopt -s nullglob
for dir in "${EXT_ROOT}"/*/; do
  meta="${dir}metadata.env"
  [[ -f "$meta" ]] || continue
  # shellcheck disable=SC1090
  EXT_ENABLED=false
  # shellcheck disable=SC1090
  source "$meta"
  if [[ "${EXT_ENABLED}" == "true" ]]; then
    printf '%s\n' "$(cd "$dir" && pwd)"
  fi
done
