# Adding extensions

## Checklist

1. Create `extensions/<ext_name>/`.
2. Add `metadata.env`, `build.sh`, `install.sh`.
3. Set `EXT_ENABLED=true`.
4. Pin a **release tag** URL and SHA256 (no floating branches).
5. Run `bash scripts/validate.sh` and `bash scripts/test.sh`.

No Dockerfile changes.

## `metadata.env`

```bash
EXT_NAME=my_ext
EXT_VERSION=1.2.3
EXT_ENABLED=true
SOURCE_URL=https://github.com/org/my_ext/archive/refs/tags/v1.2.3.tar.gz
SOURCE_SHA256=<64 hex chars>
PRIVILEGED=true
SHARED_PRELOAD=false
# PRELOAD_NAME=my_ext   # optional; defaults to EXT_NAME when SHARED_PRELOAD=true
LICENSE=MIT
HOMEPAGE=https://github.com/org/my_ext
```

| Field | Purpose |
| --- | --- |
| `EXT_ENABLED` | Discovery gate |
| `SOURCE_*` | Deterministic fetch |
| `PRIVILEGED` | Append to `supautils.privileged_extensions` when true |
| `SHARED_PRELOAD` | Append absolute `$MODS_LIBDIR/<name>` to `shared_preload_libraries` when true |

**Skip if already in the Supabase base image** (e.g. `pg_hashids`, `safeupdate`, `pg_partman`). Confirm with `pg_available_extensions` on the pinned base tag before adding a package.

## `build.sh`

Contract:

- `set -euo pipefail`
- Source `scripts/lib.sh` and `metadata.env`
- Honor `$STAGING_DIR`
- Download + verify, compile with image `pg_config`, copy `.so` / `.control` / `*.sql` into `$STAGING_DIR`
- SQL-only extensions may skip compilation and stage control + SQL only

Use helpers: `download_and_verify`, `ensure_server_headers`.

## `install.sh`

Contract:

- Read artifacts from `$STAGING_DIR`
- Call `install_shared_object` (if there is a `.so`) and `install_extension_files`

Privileged / preload registration is global (`register-privileged.sh`, `register-preload.sh`); do not duplicate it unless you have a special case.

## Testing

Extend `scripts/test.sh` with extension-specific SQL assertions, or add `extensions/<name>/test.sql` later if the suite grows.

## C vs Rust

This framework is proven for **C/PGXS** extensions. Rust/pgrx needs additional toolchain pins in the builder stage — add a second template when the first Rust extension lands rather than speculative scaffolding now.
