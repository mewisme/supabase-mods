#!/usr/bin/env bash
# Append SHARED_PRELOAD=true extensions to shared_preload_libraries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_versions

mapfile -t EXTS < <(bash "${SCRIPT_DIR}/discover.sh")
for dir in "${EXTS[@]}"; do
  SHARED_PRELOAD=false
  PRELOAD_NAME=""
  # shellcheck disable=SC1090
  source "${dir}/metadata.env"
  if [[ "${SHARED_PRELOAD}" == "true" ]]; then
    local_name="${PRELOAD_NAME:-$EXT_NAME}"
    # Absolute path: Nix pkglibdir is immutable; PG accepts full pathnames.
    append_shared_preload_library "${MODS_LIBDIR}/${local_name}"
  fi
done
