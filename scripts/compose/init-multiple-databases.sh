#!/usr/bin/env bash
# Create extra databases on first container init (empty PGDATA only).
# Used by docker-compose via /docker-entrypoint-initdb.d/.
#
# Env:
#   POSTGRES_DATABASES  comma-separated names, e.g. app,analytics,staging
#   POSTGRES_USER       bootstrap user (default supabase_admin)
#   POSTGRES_DB         already-created primary DB (used as connection target)
set -euo pipefail

dbs="${POSTGRES_DATABASES:-}"
if [[ -z "$dbs" ]]; then
  echo "POSTGRES_DATABASES unset; skipping extra database creation"
  exit 0
fi

user="${POSTGRES_USER:-supabase_admin}"
primary="${POSTGRES_DB:-postgres}"

create_db() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "ERROR: invalid database name '$name' (use [a-zA-Z_][a-zA-Z0-9_]*)" >&2
    exit 1
  fi

  # Skip if it already exists (POSTGRES_DB is created by the entrypoint).
  exists="$(psql -v ON_ERROR_STOP=1 --username "$user" --dbname "$primary" -Atc \
    "SELECT 1 FROM pg_database WHERE datname = '$name'")"
  if [[ "$exists" == "1" ]]; then
    echo "database '$name' already exists"
    return 0
  fi

  echo "creating database '$name'"
  psql -v ON_ERROR_STOP=1 --username "$user" --dbname "$primary" \
    -c "CREATE DATABASE ${name} OWNER \"${user}\";"
}

# Split on commas; trim whitespace.
IFS=',' read -ra parts <<< "$dbs"
for raw in "${parts[@]}"; do
  name="${raw#"${raw%%[![:space:]]*}"}"
  name="${name%"${name##*[![:space:]]}"}"
  [[ -n "$name" ]] || continue
  create_db "$name"
done

echo "POSTGRES_DATABASES done"
