#!/usr/bin/env bash
# Run every *.sql under /opt/supabase-mods-init/sql on first init (empty PGDATA).
# Mount your SQL files via docker-compose (see scripts/compose/sql/).
set -euo pipefail

SQL_DIR="${SQL_INIT_DIR:-/opt/supabase-mods-init/sql}"
user="${POSTGRES_USER:-supabase_admin}"
primary="${POSTGRES_DB:-postgres}"

if [[ ! -d "$SQL_DIR" ]]; then
  echo "SQL init dir missing: $SQL_DIR (skip)"
  exit 0
fi

shopt -s nullglob
files=("$SQL_DIR"/*.sql)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "no *.sql files in $SQL_DIR (skip)"
  exit 0
fi

# Deterministic order: 01-*.sql before 02-*.sql
IFS=$'\n' sorted=($(printf '%s\n' "${files[@]}" | sort))
unset IFS

for f in "${sorted[@]}"; do
  echo "running SQL init: $f"
  psql -v ON_ERROR_STOP=1 --username "$user" --dbname "$primary" -f "$f"
done

echo "SQL init done (${#sorted[@]} file(s))"
