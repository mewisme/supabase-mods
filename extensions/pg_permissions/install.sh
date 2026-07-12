#!/usr/bin/env bash
# Install staged pg_permissions (SQL-only) into the runtime image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/metadata.env"

: "${STAGING_DIR:?STAGING_DIR must be set}"

load_versions

control="${STAGING_DIR}/pg_permissions.control"
[[ -f "$control" ]] || die "missing $control"

mapfile -t sqls < <(find "$STAGING_DIR" -maxdepth 1 -name 'pg_permissions--*.sql' | sort)
[[ ${#sqls[@]} -gt 0 ]] || die "no SQL scripts in $STAGING_DIR"

install_extension_files "$control" "${sqls[@]}"

log "installed ${EXT_NAME}"
