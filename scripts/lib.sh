#!/usr/bin/env bash
# Shared helpers for supabase-mods build/install/test scripts.
# shellcheck shell=bash

set -euo pipefail

# When sourced, BASH_SOURCE[0] is this file (scripts/lib.sh).
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_LIB_DIR}/.." && pwd)"

# Logs go to stderr so command substitutions only capture return values.
log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

repo_root() {
  printf '%s\n' "$REPO_ROOT"
}

load_versions() {
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/versions.env"
  local major="${POSTGRES_MAJOR:-${DEFAULT_MAJOR:-17}}"
  local major_file="${REPO_ROOT}/versions/${major}.env"
  [[ -f "$major_file" ]] || die "missing per-major pins: $major_file"
  # shellcheck disable=SC1090
  source "$major_file"
  export DEFAULT_MAJOR
  export POSTGRES_IMAGE POSTGRES_VERSION POSTGRES_MAJOR
  export POSTGRES_SRC_VERSION POSTGRES_SRC_URL POSTGRES_SRC_SHA256
  export GLIBC_BUILDER_IMAGE
  export IMAGE_NAME MODS_LIBDIR MODS_PROFILE_OVERLAY SUPAUTILS_CONF POSTGRES_CONF
}

# Print discovered Postgres majors (from Dockerfile.N), one per line, sorted.
discover_majors() {
  local f base major
  shopt -s nullglob
  for f in "${REPO_ROOT}"/Dockerfile.[0-9]*; do
    base="$(basename "$f")"
    major="${base#Dockerfile.}"
    [[ "$major" =~ ^[0-9]+$ ]] || continue
    printf '%s\n' "$major"
  done | sort -n
}

# Highest discovered major (for `latest` tag policy).
latest_major() {
  discover_majors | tail -n1
}


# Download URL to dest and verify sha256.
download_and_verify() {
  local url="$1" dest="$2" expect="$3"
  require_cmd curl sha256sum
  log "download $url"
  curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
  local got
  got="$(sha256sum "$dest" | awk '{print $1}')"
  [[ "$got" == "$expect" ]] || die "SHA256 mismatch for $dest: got $got want $expect"
  log "verified sha256 $got"
}

# Fail if pg_config is missing or wrong major (and optionally minor) family.
abi_probe() {
  require_cmd pg_config
  local ver
  ver="$(pg_config --version)"
  log "pg_config --version: $ver"

  [[ "$ver" == *" ${POSTGRES_MAJOR}."* ]] || [[ "$ver" == *" ${POSTGRES_MAJOR} "* ]] \
    || die "ABI probe failed: expected PostgreSQL ${POSTGRES_MAJOR}.x, got: $ver"

  # Exact minor check when building directly against the runtime image.
  # Glibc builder stages may ship a newer debian pg_config while compiling
  # against copied upstream headers (see Dockerfile PG_CPPFLAGS).
  if [[ "${ABI_MAJOR_ONLY:-0}" != "1" ]]; then
    [[ "$ver" == *" ${POSTGRES_SRC_VERSION}"* ]] || [[ "$ver" == *" ${POSTGRES_SRC_VERSION}."* ]] \
      || die "ABI probe failed: expected PostgreSQL ${POSTGRES_SRC_VERSION}, got: $ver"
  else
    log "ABI_MAJOR_ONLY=1; relying on upstream headers at PG_CPPFLAGS=${PG_CPPFLAGS:-<unset>}"
    [[ -n "${PG_CPPFLAGS:-}" ]] || die "ABI_MAJOR_ONLY requires PG_CPPFLAGS (upstream headers)"
  fi

  log "pkglibdir=$(pg_config --pkglibdir)"
  log "sharedir=$(pg_config --sharedir)"
  log "includedir-server=$(pg_config --includedir-server)"
}

# Ensure server headers exist. If slim image lacks them, fetch official PG source
# and point PG_CFLAGS / CPPFLAGS at extracted src/include (after a minimal configure).
ensure_server_headers() {
  load_versions
  local inc
  inc="$(pg_config --includedir-server)"
  if [[ -f "${inc}/postgres.h" ]]; then
    log "server headers present at $inc"
    return 0
  fi

  warn "server headers missing; fetching official postgresql-${POSTGRES_SRC_VERSION} sources for headers"
  require_cmd tar make
  local work="${HEADER_CACHE_DIR:-/tmp/pg-headers}"
  mkdir -p "$work"
  local tarball="$work/postgresql-${POSTGRES_SRC_VERSION}.tar.bz2"
  local srcdir="$work/postgresql-${POSTGRES_SRC_VERSION}"

  if [[ ! -f "$srcdir/src/include/postgres.h" ]]; then
    download_and_verify "$POSTGRES_SRC_URL" "$tarball" "$POSTGRES_SRC_SHA256"
    tar -xjf "$tarball" -C "$work"
    # Minimal configure so pg_config.h exists for extension builds.
    (
      cd "$srcdir"
      ./configure --without-readline --without-zlib >/tmp/pg-configure.log 2>&1 \
        || die "postgresql configure failed; see /tmp/pg-configure.log"
    )
  fi

  export PG_CPPFLAGS="-I${srcdir}/src/include"
  export CPPFLAGS="${PG_CPPFLAGS} ${CPPFLAGS:-}"
  export CFLAGS="${CFLAGS:--O2} ${PG_CPPFLAGS}"
  log "using header fallback: $PG_CPPFLAGS"
}

# Ensure SHAREDIR/extension is writable.
#
# Upstream packs Postgres in the Nix store (immutable). pg_config --sharedir
# resolves through /nix/var/nix/profiles/default. We retarget that profile
# symlink to a writable copy under /opt/supabase-mods/nix-profile so control
# files can be installed without modifying the store.
materialize_extension_dir() {
  require_cmd pg_config
  load_versions

  local profile_link="/nix/var/nix/profiles/default"
  local overlay="${MODS_PROFILE_OVERLAY:-/opt/supabase-mods/nix-profile}"
  local sharedir ext_dir marker real_profile real_share

  sharedir="$(pg_config --sharedir)"
  ext_dir="${sharedir}/extension"
  marker="${overlay}/.supabase-mods-overlay"

  if [[ -f "$marker" ]] && touch "${ext_dir}/.write-test" 2>/dev/null; then
    rm -f "${ext_dir}/.write-test"
    printf '%s\n' "$ext_dir"
    return 0
  fi

  if touch "${ext_dir}/.write-test" 2>/dev/null; then
    rm -f "${ext_dir}/.write-test"
    log "extension dir already writable: $ext_dir"
    printf '%s\n' "$ext_dir"
    return 0
  fi

  [[ -L "$profile_link" || -e "$profile_link" ]] \
    || die "expected nix profile link at $profile_link"

  real_profile="$(readlink -f "$profile_link")"
  real_share="$(readlink -f "$sharedir")"
  log "materialize nix profile overlay: $real_profile -> $overlay"

  rm -rf "$overlay"
  mkdir -p "$overlay"
  cp -a "$real_profile"/. "$overlay"/

  # Replace share/postgresql with a real writable tree.
  rm -rf "${overlay}/share/postgresql"
  mkdir -p "${overlay}/share/postgresql"
  cp -a "$real_share"/. "${overlay}/share/postgresql"/
  chmod -R u+w "${overlay}/share/postgresql"

  ln -sfn "$overlay" "$profile_link"
  touch "$marker"

  sharedir="$(pg_config --sharedir)"
  ext_dir="${sharedir}/extension"
  touch "${ext_dir}/.write-test" || die "overlay failed: $ext_dir still not writable"
  rm -f "${ext_dir}/.write-test"
  log "extension dir ready: $ext_dir"
  printf '%s\n' "$ext_dir"
}

# Install a .so under MODS_LIBDIR and rewrite module_pathname in the control file.
# Args: so_path control_path [ext_name]
install_shared_object() {
  load_versions
  local so_path="$1" control_path="$2"
  local base name dest_so
  base="$(basename "$so_path")"
  name="${base%.so}"

  mkdir -p "$MODS_LIBDIR"
  dest_so="${MODS_LIBDIR}/${base}"
  install -m 0755 "$so_path" "$dest_so"
  log "installed $dest_so"

  # PG17: $libdir is pkglibdir (often Nix/immutable). Absolute path is safest.
  if [[ -f "$control_path" ]]; then
    sed -i "s|^module_pathname *=.*|module_pathname = '${MODS_LIBDIR}/${name}'|" "$control_path" \
      || die "failed to rewrite module_pathname in $control_path"
    # If no module_pathname line existed, append one.
    if ! grep -q '^module_pathname' "$control_path"; then
      printf "module_pathname = '%s/%s'\n" "$MODS_LIBDIR" "$name" >>"$control_path"
    fi
    log "rewrote module_pathname in $control_path"
  fi
}

# Install control + SQL scripts into materialized SHAREDIR/extension.
# SQL that hardcodes '$libdir/...' (instead of MODULE_PATHNAME) is rewritten
# to MODS_LIBDIR so CREATE FUNCTION can find our staged .so files.
install_extension_files() {
  load_versions
  local ext_dir
  ext_dir="$(materialize_extension_dir)"
  local f dest tmp
  for f in "$@"; do
    [[ -f "$f" ]] || die "missing extension file: $f"
    dest="${ext_dir}/$(basename "$f")"
    if [[ "$f" == *.sql ]]; then
      tmp="$(mktemp)"
      # Escape for sed: $libdir/foo -> /opt/.../foo
      sed "s|\\\$libdir/|${MODS_LIBDIR}/|g" "$f" >"$tmp"
      install -m 0644 "$tmp" "$dest"
      rm -f "$tmp"
    else
      install -m 0644 "$f" "$dest"
    fi
    log "installed $(basename "$f") -> $ext_dir"
  done
}

# Append extension name to supautils.privileged_extensions (idempotent).
append_privileged_extension() {
  load_versions
  local name="$1"
  local conf="${SUPAUTILS_CONF}"
  [[ -f "$conf" ]] || die "supautils conf not found: $conf"

  # Already present?
  if grep -Eq "supautils\.privileged_extensions *= *'[^']*\b${name}\b" "$conf"; then
    log "privileged_extensions already contains $name"
    return 0
  fi

  # Append before closing quote on the privileged_extensions line.
  if grep -q "supautils.privileged_extensions" "$conf"; then
    sed -i -E "s/(supautils\.privileged_extensions *= *')([^']*)(')/\1\2, ${name}\3/" "$conf" \
      || die "failed to append $name to privileged_extensions"
    log "appended $name to privileged_extensions"
  else
    printf "supautils.privileged_extensions = '%s'\n" "$name" >>"$conf"
    log "created privileged_extensions with $name"
  fi
}

# Append a library to shared_preload_libraries in POSTGRES_CONF (idempotent).
# Prefer absolute paths under MODS_LIBDIR so Nix $libdir stays untouched.
# Arg: library entry (basename or absolute path without .so).
append_shared_preload_library() {
  load_versions
  local entry="$1"
  local conf="${POSTGRES_CONF:-/etc/postgresql/postgresql.conf}"
  [[ -f "$conf" ]] || die "postgresql.conf not found: $conf"
  [[ -n "$entry" ]] || die "append_shared_preload_library: empty entry"

  # Match bare name or already-absolute path (basename of entry).
  local bare
  bare="$(basename "$entry")"
  if grep -Eq "shared_preload_libraries *= *'[^']*(^|[, ])${bare}([, ']|$)" "$conf" \
    || grep -Fq "$entry" "$conf"; then
    log "shared_preload_libraries already contains $entry"
    return 0
  fi

  if grep -q "^[[:space:]]*shared_preload_libraries[[:space:]]*=" "$conf"; then
    sed -i -E "s|^([[:space:]]*shared_preload_libraries[[:space:]]*=[[:space:]]*')([^']*)('.*)|\1\2, ${entry}\3|" "$conf" \
      || die "failed to append $entry to shared_preload_libraries"
    log "appended $entry to shared_preload_libraries"
  else
    printf "shared_preload_libraries = '%s'\n" "$entry" >>"$conf"
    log "created shared_preload_libraries with $entry"
  fi
}
