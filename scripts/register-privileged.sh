#!/usr/bin/env bash
# Append PRIVILEGED=true extensions to supautils.privileged_extensions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_versions

mapfile -t EXTS < <(bash "${SCRIPT_DIR}/discover.sh")
for dir in "${EXTS[@]}"; do
  PRIVILEGED=false
  # shellcheck disable=SC1090
  source "${dir}/metadata.env"
  if [[ "${PRIVILEGED}" == "true" ]]; then
    append_privileged_extension "$EXT_NAME"
  fi
done
