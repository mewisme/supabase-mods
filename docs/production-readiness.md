# Production readiness report

Audit date: 2026-07-12  
Scope: greenfield `supabase-mods` repository after initial implementation.

## Architecture overview

`supabase-mods` is a multi-extension distribution layered on pinned Supabase Postgres:

- **Runtime:** `supabase/postgres:17.6.1.143` (Alpine outer image, Nix-packaged **glibc** Postgres)
- **Builder:** `postgres:17.6-bookworm` (glibc + PGXS), with server headers copied from the runtime image
- **Framework:** `extensions/<name>/{metadata.env,build.sh,install.sh}` discovered by `scripts/*-all.sh`
- **First extension:** `pg_uuidv7` 1.7.0 (source tarball + SHA256)

```text
abi (supabase) --headers--> builder (glibc) --/staging--> runtime (supabase)
```

## Implementation decisions

| Decision | Rationale |
| --- | --- |
| Glibc builder, not Alpine gcc | Runtime Postgres is Nix/glibc; musl `.so` fails to load |
| Absolute `module_pathname` under `/opt/supabase-mods/lib` | Avoids writing into immutable Nix `$libdir` |
| Append to `supautils.privileged_extensions` | Official Supabase mechanism for non-superuser `CREATE EXTENSION` |
| No auto-`CREATE EXTENSION` on boot | Max upstream behavioral compatibility |
| `ABI_MAJOR_ONLY` in glibc stage | Debian `postgresql-server-dev-17` may be newer (e.g. 17.10); headers come from Supabase 17.6 |
| Nix profile overlay helper | Available if install cannot write through the profile path; Docker build layers usually allow direct writes |

## Compatibility review

- Upstream `ENTRYPOINT` / `CMD` / healthcheck preserved (not redefined).
- Config layout and `supabase_admin` bootstrap user unchanged.
- `pg_uuidv7` registered in privileged extensions list.
- Verified locally: `CREATE EXTENSION`, `uuid_generate_v7()`, restart survival.

## Security review

- Base image and extension source pinned; SHA256 verified on download.
- No floating `latest` / `multigres` base tags.
- Runtime image contains no compilers.
- Scripts use `set -euo pipefail`.
- Secrets for publish are CI-only (`DOCKERHUB_*`).

## CI/CD review

- Validate → discover majors → build/test. Publish only on `v*` tags.
- Multi-arch publish: `linux/amd64`, `linux/arm64`.
- Per-major tags: `17`, `17.6.1.143`, `17-b{run_number}`, `latest` (max major on tag publish), git tags.
- Failure artifacts for logs.

## Docker review

- Per-major `Dockerfile.N` + `versions/N.env`.
- Multi-stage, BuildKit syntax `1.7`.
- OCI labels on runtime image.
- Compose selects `Dockerfile.${POSTGRES_MAJOR}`.

## PostgreSQL review

- Extension control/SQL installed into `SHAREDIR/extension`.
- Shared library glibc-linked and loadable by Nix Postgres.
- Privileged allowlist updated idempotently.

## Issues discovered during implementation

1. **Musl vs glibc trap** — Alpine outer image misleads; compiling with `apk` gcc produces unloadable modules. Fixed with glibc builder.
2. **Stdout pollution** — `log` wrote to stdout and broke `$(materialize_extension_dir)`. Logs now go to stderr.
3. **Nix immutable paths** — Extension dir is under Nix profile; Docker build layers make writes persist; overlay helper retained for robustness.
4. **UUIDv7 same-ms ordering** — Burst generates are not strictly sortable; tests space samples.

## Improvements made

- Modular extension framework without Dockerfile per-extension logic.
- Fail-fast automated test suite covering the plan’s acceptance checks.
- Documentation of ABI/supautils/Nix realities for future maintainers.

## Remaining limitations

- Glibc builder’s apt `postgresql-server-dev-17` may not match Supabase’s exact minor; mitigated by copying upstream headers.
- No image signing / SBOM yet.
- No Rust/pgrx template yet (YAGNI until a Rust extension is added).
- Hosted Supabase Cloud will not include these mods.
- Multi-arch is exercised in CI publish; local tests run on the host architecture only.

## Future recommendations

1. Add Dependabot/renovate for `POSTGRES_IMAGE` and extension pins.
2. Generate SBOM + cosign signatures on release tags.
3. When PG18+ is adopted upstream, prefer `extension_control_path` over Nix profile materialization.
4. Add a second C extension to prove the framework scales, then consider pgrx.

## Production readiness score

**8.5 / 10**

Deduction for: apt server-dev minor drift vs exact Nix postgres, missing signing/SBOM, and single bundled extension (framework proven, catalog still small). Core build, ABI, tests, CI, and docs are production-usable for self-hosted deployments.
