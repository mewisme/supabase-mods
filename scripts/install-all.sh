#!/usr/bin/env bash
# Install all enabled extensions from STAGING_ROOT into the runtime image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_versions

STAGING_ROOT="${STAGING_ROOT:-/staging}"
[[ -d "$STAGING_ROOT" ]] || die "staging root missing: $STAGING_ROOT"

mapfile -t EXTS < <("${SCRIPT_DIR}/discover.sh")
[[ ${#EXTS[@]} -gt 0 ]] || die "no enabled extensions found"

for dir in "${EXTS[@]}"; do
  # shellcheck disable=SC1090
  source "${dir}/metadata.env"
  log "installing ${EXT_NAME}"
  export STAGING_DIR="${STAGING_ROOT}/${EXT_NAME}"
  export EXT_DIR="$dir"
  [[ -d "$STAGING_DIR" ]] || die "staging missing for ${EXT_NAME}: $STAGING_DIR"
  bash "${dir}/install.sh"
done

"${SCRIPT_DIR}/register-privileged.sh"

log "all extensions installed"
