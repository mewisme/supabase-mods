#!/usr/bin/env bash
# Install staged pg_wait_sampling artifacts into the runtime image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/metadata.env"

: "${STAGING_DIR:?STAGING_DIR must be set}"

load_versions

so="${STAGING_DIR}/pg_wait_sampling.so"
control="${STAGING_DIR}/pg_wait_sampling.control"
[[ -f "$so" ]] || die "missing $so"
[[ -f "$control" ]] || die "missing $control"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -a "$control" "${tmp}/pg_wait_sampling.control"
install_shared_object "$so" "${tmp}/pg_wait_sampling.control"

mapfile -t sqls < <(find "$STAGING_DIR" -maxdepth 1 -name 'pg_wait_sampling--*.sql' | sort)
[[ ${#sqls[@]} -gt 0 ]] || die "no SQL scripts in $STAGING_DIR"

install_extension_files "${tmp}/pg_wait_sampling.control" "${sqls[@]}"

log "installed ${EXT_NAME}"
