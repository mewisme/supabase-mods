#!/usr/bin/env bash
# End-to-end image validation. Fail immediately on any error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_versions
ROOT="$(repo_root)"
cd "$ROOT"

require_cmd docker

COMPOSE=(docker compose)
PROJECT="supabase-mods-test-$$"
export COMPOSE_PROJECT_NAME="$PROJECT"

LOG_DIR="${ROOT}/test-output"
mkdir -p "$LOG_DIR"
BUILD_LOG="${LOG_DIR}/build.log"
TEST_LOG="${LOG_DIR}/test.log"

cleanup() {
  "${COMPOSE[@]}" -f docker-compose.yml down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql_admin() {
  local sql="$1"
  docker exec -i "${PROJECT}-db-1" \
    psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-supabase_admin}" -d "${POSTGRES_DB:-postgres}" -tAc "$sql" \
    2>>"$TEST_LOG"
}

# Compose service container name with project prefix.
wait_healthy() {
  local cid status
  local tries=60
  local i
  for i in $(seq 1 "$tries"); do
    cid="$("${COMPOSE[@]}" ps -q db)"
    [[ -n "$cid" ]] || { sleep 2; continue; }
    status="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)"
    log "health: $status ($i/$tries)"
    if [[ "$status" == "healthy" ]]; then
      return 0
    fi
    if [[ "$status" == "unhealthy" ]]; then
      docker logs "$cid" | tee -a "$TEST_LOG" || true
      die "container became unhealthy"
    fi
    sleep 2
  done
  docker logs "$("${COMPOSE[@]}" ps -q db)" | tee -a "$TEST_LOG" || true
  die "timed out waiting for healthy"
}

log "validate static layout"
bash "${SCRIPT_DIR}/validate.sh"

# Ensure .env exists for compose.
if [[ ! -f .env ]]; then
  cp .env.example .env
fi
# shellcheck disable=SC1091
source .env
export POSTGRES_MAJOR="${POSTGRES_MAJOR:-${DEFAULT_MAJOR:-17}}"
export POSTGRES_USER="${POSTGRES_USER:-supabase_admin}"
export POSTGRES_DB="${POSTGRES_DB:-postgres}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
export POSTGRES_IMAGE POSTGRES_VERSION GLIBC_BUILDER_IMAGE IMAGE_NAME

# Reload pins for the selected major (in case .env only set MAJOR).
load_versions
export POSTGRES_IMAGE POSTGRES_VERSION GLIBC_BUILDER_IMAGE

log "build image (Dockerfile.${POSTGRES_MAJOR})"
"${COMPOSE[@]}" build db 2>&1 | tee "$BUILD_LOG"

log "start stack"
"${COMPOSE[@]}" up -d db
wait_healthy

# Resolve actual container (compose v2 naming).
DB_CID="$("${COMPOSE[@]}" ps -q db)"
DB_NAME="$(docker inspect -f '{{.Name}}' "$DB_CID" | sed 's#^/##')"

psql_in() {
  docker exec -i "$DB_CID" \
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"
}

run_sql() {
  psql_in -tAc "$1"
}

log "CREATE EXTENSION pg_uuidv7"
run_sql "CREATE EXTENSION pg_uuidv7;"

log "idempotent CREATE EXTENSION IF NOT EXISTS"
run_sql "CREATE EXTENSION IF NOT EXISTS pg_uuidv7;"

log "uuid_generate_v7() smoke"
uuid1="$(run_sql "SELECT uuid_generate_v7();" | tr -d '[:space:]')"
[[ -n "$uuid1" ]] || die "empty uuid"
[[ "$uuid1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
  || die "invalid UUID format: $uuid1"

# Version nibble is the first character of the third group (RFC 4122).
ver_char="$(printf '%s' "$uuid1" | cut -d- -f3 | cut -c1)"
[[ "$ver_char" == "7" ]] || die "UUID version is $ver_char, want 7 ($uuid1)"
log "UUID version OK: $uuid1"

log "uniqueness across 20 samples"
uniq_count="$(run_sql "SELECT count(DISTINCT u) FROM (SELECT uuid_generate_v7() AS u FROM generate_series(1,20)) s;")"
[[ "$uniq_count" == "20" ]] || die "expected 20 unique UUIDs, got $uniq_count"

log "timestamp ordering (spaced samples)"
# Same-millisecond UUIDv7 values may not lexicographically sort; space samples in the client.
prev=""
for i in 1 2 3 4 5; do
  cur="$(run_sql "SELECT uuid_generate_v7();" | tr -d '[:space:]')"
  if [[ -n "$prev" ]]; then
    # Lexicographic compare works for UUIDv7 across distinct timestamps.
    if ! [[ "$prev" < "$cur" ]]; then
      die "UUIDv7 timestamp ordering failed: prev=$prev cur=$cur"
    fi
  fi
  prev="$cur"
  sleep 0.01
done
log "timestamp ordering OK"

log "CREATE EXTENSION pg_permissions"
run_sql "CREATE EXTENSION pg_permissions;"
perm_n="$(run_sql "SELECT count(*) FROM all_permissions;" | tr -d '[:space:]')"
[[ "$perm_n" =~ ^[0-9]+$ ]] || die "all_permissions failed: $perm_n"
log "pg_permissions OK (all_permissions rows=$perm_n)"

log "CREATE EXTENSION pg_wait_sampling"
run_sql "CREATE EXTENSION pg_wait_sampling;"
wait_n="$(run_sql "SELECT count(*) FROM pg_wait_sampling_current;" | tr -d '[:space:]')"
[[ "$wait_n" =~ ^[0-9]+$ ]] || die "pg_wait_sampling_current failed: $wait_n"
log "pg_wait_sampling OK (current rows=$wait_n)"

log "CREATE EXTENSION pg_stat_statements + pg_stat_kcache"
run_sql "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
run_sql "CREATE EXTENSION pg_stat_kcache;"
kcache_n="$(run_sql "SELECT count(*) FROM pg_stat_kcache;" | tr -d '[:space:]')"
[[ "$kcache_n" =~ ^[0-9]+$ ]] || die "pg_stat_kcache failed: $kcache_n"
log "pg_stat_kcache OK (rows=$kcache_n)"

log "CREATE EXTENSION pg_ivm"
run_sql "CREATE EXTENSION pg_ivm;"
run_sql "SELECT pgivm.create_immv('public.immv_smoke', 'SELECT 1 AS x');"
immv_n="$(run_sql "SELECT count(*) FROM public.immv_smoke;" | tr -d '[:space:]')"
[[ "$immv_n" == "1" ]] || die "immv_smoke expected 1 row, got $immv_n"
run_sql "DROP TABLE public.immv_smoke;"
log "pg_ivm OK"

log "restart container"
docker restart "$DB_CID" >/dev/null
wait_healthy

log "extension still works after restart"
uuid2="$(run_sql "SELECT uuid_generate_v7();" | tr -d '[:space:]')"
[[ "$uuid2" =~ ^[0-9a-fA-F-]{36}$ ]] || die "post-restart uuid failed: $uuid2"
ver2="$(printf '%s' "$uuid2" | cut -d- -f3 | cut -c1)"
[[ "$ver2" == "7" ]] || die "post-restart version not 7"

log "preload extensions still queryable after restart"
run_sql "SELECT count(*) FROM pg_wait_sampling_current;" >/dev/null
run_sql "SELECT count(*) FROM pg_stat_kcache;" >/dev/null

log "scan logs for FATAL/PANIC"
docker logs "$DB_CID" >"${LOG_DIR}/postgres.log" 2>&1 || true
# Filter known benign noise; fail on unexpected FATAL/PANIC.
if grep -E 'FATAL:|PANIC:' "${LOG_DIR}/postgres.log" | grep -Ev 'role ".*" does not exist|password authentication failed|the database system is starting up|database system is shutting down' >/tmp/pg-fatal.txt; then
  if [[ -s /tmp/pg-fatal.txt ]]; then
    cat /tmp/pg-fatal.txt | tee -a "$TEST_LOG"
    die "unexpected FATAL/PANIC in postgres logs"
  fi
fi

log "ALL TESTS PASSED"
printf 'container=%s uuid_sample=%s\n' "$DB_NAME" "$uuid1" | tee -a "$TEST_LOG"
