#!/usr/bin/env bash
# Static validation of the repository (no Docker required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_versions
ROOT="$(repo_root)"
fail=0

[[ "$POSTGRES_IMAGE" != *latest* ]] || die "POSTGRES_IMAGE must not use latest"
[[ "$POSTGRES_IMAGE" != *multigres* ]] || die "POSTGRES_IMAGE must not use multigres"

required_files=(
  "$ROOT/docker-compose.yml"
  "$ROOT/.env.example"
  "$ROOT/versions.env"
  "$ROOT/README.md"
  "$ROOT/LICENSE"
  "$ROOT/scripts/lib.sh"
  "$ROOT/scripts/discover.sh"
  "$ROOT/scripts/build-all.sh"
  "$ROOT/scripts/install-all.sh"
  "$ROOT/scripts/register-privileged.sh"
  "$ROOT/scripts/validate.sh"
  "$ROOT/scripts/test.sh"
  "$ROOT/.github/workflows/docker.yml"
)

for f in "${required_files[@]}"; do
  [[ -f "$f" ]] || { warn "missing file: $f"; fail=1; }
done

mapfile -t MAJORS < <(discover_majors)
[[ ${#MAJORS[@]} -gt 0 ]] || { warn "no Dockerfile.[0-9]+ tracks found"; fail=1; }

for major in "${MAJORS[@]}"; do
  df="$ROOT/Dockerfile.${major}"
  vf="$ROOT/versions/${major}.env"
  [[ -f "$df" ]] || { warn "missing $df"; fail=1; continue; }
  [[ -f "$vf" ]] || { warn "missing $vf for Dockerfile.${major}"; fail=1; continue; }

  if grep -Eiq '^(ENTRYPOINT|CMD)[[:space:]]' "$df"; then
    warn "Dockerfile.${major} must not set ENTRYPOINT/CMD (preserve upstream)"
    fail=1
  fi
  while IFS= read -r line; do
    if [[ ! "$line" =~ ^USER[[:space:]]+root[[:space:]]*$ ]]; then
      warn "Dockerfile.${major} USER must be root if set (found: $line)"
      fail=1
    fi
  done < <(grep -E '^USER[[:space:]]+' "$df" || true)

  if grep -Eiq 'postgres:latest|:latest' "$vf"; then
    warn "versions/${major}.env contains latest"
    fail=1
  fi
  if grep -Eiq 'multigres' "$vf"; then
    warn "versions/${major}.env must not use multigres"
    fail=1
  fi
done

# Every enabled extension must have the contract files.
mapfile -t EXTS < <("${SCRIPT_DIR}/discover.sh")
[[ ${#EXTS[@]} -gt 0 ]] || { warn "no enabled extensions"; fail=1; }

for dir in "${EXTS[@]}"; do
  for need in metadata.env build.sh install.sh; do
    [[ -f "${dir}/${need}" ]] || { warn "missing ${dir}/${need}"; fail=1; }
  done
  # shellcheck disable=SC1090
  source "${dir}/metadata.env"
  for var in EXT_NAME EXT_VERSION EXT_ENABLED SOURCE_URL SOURCE_SHA256 PRIVILEGED; do
    [[ -n "${!var:-}" ]] || { warn "${dir}: missing $var"; fail=1; }
  done
  [[ "$SOURCE_URL" != *"/branch/"* ]] || { warn "${dir}: SOURCE_URL must not point at a branch"; fail=1; }
  [[ ${#SOURCE_SHA256} -eq 64 ]] || { warn "${dir}: SOURCE_SHA256 must be 64 hex chars"; fail=1; }
  grep -q 'set -euo pipefail' "${dir}/build.sh" || { warn "${dir}/build.sh missing set -euo pipefail"; fail=1; }
  grep -q 'set -euo pipefail' "${dir}/install.sh" || { warn "${dir}/install.sh missing set -euo pipefail"; fail=1; }
done

[[ "$fail" -eq 0 ]] || die "validation failed"
log "validation passed (majors: ${MAJORS[*]})"
