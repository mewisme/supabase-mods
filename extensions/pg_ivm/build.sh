#!/usr/bin/env bash
# Build pg_ivm from pinned upstream source into $STAGING_DIR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/metadata.env"

: "${STAGING_DIR:?STAGING_DIR must be set}"

require_cmd make pg_config tar
load_versions

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tarball="${work}/src.tar.gz"
download_and_verify "$SOURCE_URL" "$tarball" "$SOURCE_SHA256"
tar -xzf "$tarball" -C "$work"
srcdir="${work}/pg_ivm-${EXT_VERSION}"
[[ -d "$srcdir" ]] || srcdir="$(find "$work" -maxdepth 1 -type d -name 'pg_ivm-*' | head -n1)"
[[ -d "$srcdir" ]] || die "extracted source directory not found"

ensure_server_headers

log "compiling ${EXT_NAME} against $(pg_config --version)"
make -C "$srcdir" clean || true
make -C "$srcdir" USE_PGXS=1 PG_CONFIG="$(command -v pg_config)" \
  CPPFLAGS="${PG_CPPFLAGS:-} ${CPPFLAGS:-}" \
  CFLAGS="${CFLAGS:--O2} ${PG_CPPFLAGS:-}"

mkdir -p "$STAGING_DIR"
find "$srcdir" -maxdepth 2 -name '*.so' -exec cp -a {} "$STAGING_DIR/" \;
find "$srcdir" -maxdepth 2 -name '*.control' -exec cp -a {} "$STAGING_DIR/" \;
find "$srcdir" -maxdepth 1 -name 'pg_ivm--*.sql' -exec cp -a {} "$STAGING_DIR/" \;

[[ -f "${STAGING_DIR}/pg_ivm.so" ]] || die "build did not produce pg_ivm.so"
[[ -f "${STAGING_DIR}/pg_ivm.control" ]] || die "build did not produce pg_ivm.control"
ls "${STAGING_DIR}"/pg_ivm--*.sql >/dev/null 2>&1 || die "build did not produce SQL script"

log "staged ${EXT_NAME} -> ${STAGING_DIR}"
ls -la "$STAGING_DIR"
