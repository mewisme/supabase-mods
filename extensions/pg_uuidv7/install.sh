#!/usr/bin/env bash
# Install staged pg_uuidv7 artifacts into the runtime image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/metadata.env"

: "${STAGING_DIR:?STAGING_DIR must be set}"

load_versions

so="${STAGING_DIR}/pg_uuidv7.so"
control="${STAGING_DIR}/pg_uuidv7.control"
[[ -f "$so" ]] || die "missing $so"
[[ -f "$control" ]] || die "missing $control"

# Copy control into a temp location so we can rewrite module_pathname before install.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -a "$control" "${tmp}/pg_uuidv7.control"
install_shared_object "$so" "${tmp}/pg_uuidv7.control"

mapfile -t sqls < <(find "$STAGING_DIR" -maxdepth 1 -name 'pg_uuidv7--*.sql' | sort)
[[ ${#sqls[@]} -gt 0 ]] || die "no SQL scripts in $STAGING_DIR"

install_extension_files "${tmp}/pg_uuidv7.control" "${sqls[@]}"

log "installed ${EXT_NAME}"
