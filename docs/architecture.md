# Architecture

## Problem

Native PostgreSQL extensions are shared libraries linked against a specific PostgreSQL ABI and C library. Compiling against stock `postgres:17` (glibc) and loading into Supabase’s Alpine/Nix image (musl + Nix store) is undefined behavior.

## Base image reality

`supabase/postgres:17.6.1.143` (from upstream `Dockerfile-17`) is:

- Alpine 3.23
- PostgreSQL and extensions installed via Nix profiles
- Symlink farms under `/usr/lib/postgresql` and `/usr/share/postgresql` into `/nix/...`
- `session_preload_libraries = 'supautils'`
- Custom config under `/etc/postgresql` and `/etc/postgresql-custom`
- Bootstrap user `supabase_admin`
- Official docker-entrypoint preserved

## ABI strategy

1. **Runtime** `FROM` the exact Supabase tag (`supabase/postgres:17.6.1.143`).
2. **Compile** on a **glibc** builder (`postgres:17.6-bookworm`), not Alpine/`apk` gcc.

Why: the Alpine outer image is misleading. Upstream ships Nix-built PostgreSQL binaries linked against **glibc** (`ld-linux-x86-64.so.2` in the Nix store). A musl-built `.so` will not load into that process (`libc.musl-x86_64.so.1` / relocation failures).

3. Copy upstream server headers from the Supabase image into the glibc builder (`/opt/supabase-abi/include`) and pass them via `PG_CPPFLAGS` so types/macros match the runtime catalog.
4. Use Debian PGXS/`pg_config` only as the build orchestration (same PG **17.6** major/minor family).
5. Probe version; fail if not PostgreSQL 17.6 family.
6. Runtime stage copies only staged artifacts; never redefine ENTRYPOINT/CMD.

This is the safest practical approach without rebuilding Supabase’s entire Nix flake.

## Install layout (PostgreSQL 17)

PostgreSQL 17 has **no** `extension_control_path` (added in PG 18). Control and SQL files must live in `SHAREDIR/extension`.

Because that directory is often a symlink into an immutable Nix store, install:

1. **Materializes** `SHAREDIR/extension` into a writable directory (copy upstream files, then add ours).
2. Places `.so` files under `/opt/supabase-mods/lib`.
3. Rewrites `module_pathname` in `.control` to an **absolute** path under `/opt/supabase-mods/lib`, avoiding `$libdir` (pkglibdir) writes.

## Supabase / supautils

`supautils.privileged_extensions` lists extensions that non-superusers may create via delegation to the configured superuser.

Our `register-privileged.sh` **appends** enabled `PRIVILEGED=true` extension names to `/etc/postgresql-custom/supautils.conf`. It never replaces the upstream list.

We do not auto-run `CREATE EXTENSION` on boot.

## Extension framework

```text
discover.sh  -> enabled package dirs
build-all.sh -> for each: build.sh -> /staging/<name>/
install-all.sh -> for each: install.sh; then register-privileged.sh
```

The per-major Dockerfile (`Dockerfile.17`, …) contains **no** per-extension logic. Adding an extension is a new directory under `extensions/`. Adding a Postgres major is a new `Dockerfile.N` + `versions/N.env`.

## Multi-major tracks

Each Postgres major has its own Dockerfile and pin file:

```text
Dockerfile.17 + versions/17.env
Dockerfile.18 + versions/18.env   # when Supabase ships PG18
```

CI discovers `Dockerfile.[0-9]+`. Image tag `latest` follows the **highest** major present. Until `Dockerfile.18` exists, `latest` stays on 17.

## Multi-stage image

| Stage | Base | Role |
| --- | --- | --- |
| `abi` | `supabase/postgres:17.6.1.143` | Export server headers |
| `builder` | `postgres:17.6-bookworm` (glibc) | Compile extensions with PGXS |
| `runtime` | `supabase/postgres:17.6.1.143` | Install artifacts only |

Entrypoint, CMD, USER, and healthcheck are inherited unchanged from the runtime base.
