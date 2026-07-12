#!/usr/bin/env bash
# Install staged pg_stat_kcache artifacts into the runtime image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/metadata.env"

: "${STAGING_DIR:?STAGING_DIR must be set}"

load_versions

so="${STAGING_DIR}/pg_stat_kcache.so"
control="${STAGING_DIR}/pg_stat_kcache.control"
[[ -f "$so" ]] || die "missing $so"
[[ -f "$control" ]] || die "missing $control"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -a "$control" "${tmp}/pg_stat_kcache.control"
install_shared_object "$so" "${tmp}/pg_stat_kcache.control"

mapfile -t sqls < <(find "$STAGING_DIR" -maxdepth 1 -name 'pg_stat_kcache--*.sql' | sort)
[[ ${#sqls[@]} -gt 0 ]] || die "no SQL scripts in $STAGING_DIR"

install_extension_files "${tmp}/pg_stat_kcache.control" "${sqls[@]}"

log "installed ${EXT_NAME}"
