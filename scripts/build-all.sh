#!/usr/bin/env bash
# Build all enabled extensions into STAGING_ROOT/<EXT_NAME>/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_versions
require_cmd bash

STAGING_ROOT="${STAGING_ROOT:-/staging}"
mkdir -p "$STAGING_ROOT"

abi_probe
ensure_server_headers

mapfile -t EXTS < <(bash "${SCRIPT_DIR}/discover.sh")
[[ ${#EXTS[@]} -gt 0 ]] || die "no enabled extensions found"

for dir in "${EXTS[@]}"; do
  # shellcheck disable=SC1090
  source "${dir}/metadata.env"
  log "building ${EXT_NAME} ${EXT_VERSION}"
  export STAGING_DIR="${STAGING_ROOT}/${EXT_NAME}"
  mkdir -p "$STAGING_DIR"
  export EXT_DIR="$dir"
  bash "${dir}/build.sh"
done

log "all extensions built into ${STAGING_ROOT}"
