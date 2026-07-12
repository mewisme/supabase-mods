#!/usr/bin/env bash
# Print discovered Postgres majors (Dockerfile.N), one per line.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
discover_majors
