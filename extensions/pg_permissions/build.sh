#!/usr/bin/env bash
# Stage SQL-only pg_permissions (no shared library).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/metadata.env"

: "${STAGING_DIR:?STAGING_DIR must be set}"

require_cmd tar
load_versions

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tarball="${work}/src.tar.gz"
download_and_verify "$SOURCE_URL" "$tarball" "$SOURCE_SHA256"
tar -xzf "$tarball" -C "$work"
srcdir="${work}/pg_permissions-REL_1_4_1"
[[ -d "$srcdir" ]] || srcdir="$(find "$work" -maxdepth 1 -type d -name 'pg_permissions-*' | head -n1)"
[[ -d "$srcdir" ]] || die "extracted source directory not found"

mkdir -p "$STAGING_DIR"
cp -a "${srcdir}/pg_permissions.control" "$STAGING_DIR/"
# Extension SQL scripts (install + upgrade paths).
find "$srcdir" -maxdepth 1 -name 'pg_permissions--*.sql' -exec cp -a {} "$STAGING_DIR/" \;

# ponytail: REL_1_4_1 ships default_version=1.4 but only 1.3 install + 1.3--1.4 upgrade.
# Synthesize --1.4.sql so CREATE EXTENSION works without a two-step dance.
if [[ ! -f "${STAGING_DIR}/pg_permissions--1.4.sql" ]]; then
  {
    printf '%s\n' '\echo Use "CREATE EXTENSION pg_permissions" to load this file. \quit'
    # Body of 1.3 install (skip its \echo guard).
    grep -v '^\\echo' "${srcdir}/pg_permissions--1.3.sql"
    # Body of upgrade to 1.4 (skip its \echo guard).
    grep -v '^\\echo' "${srcdir}/pg_permissions--1.3--1.4.sql"
  } >"${STAGING_DIR}/pg_permissions--1.4.sql"
  log "synthesized pg_permissions--1.4.sql from 1.3 + 1.3--1.4"
fi

[[ -f "${STAGING_DIR}/pg_permissions.control" ]] || die "missing control"
[[ -f "${STAGING_DIR}/pg_permissions--1.4.sql" ]] || die "missing install SQL"

log "staged ${EXT_NAME} -> ${STAGING_DIR}"
ls -la "$STAGING_DIR"
