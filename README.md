# supabase-mods

PostgreSQL extension distribution built on pinned [Supabase Postgres](https://github.com/supabase/postgres).

`supabase-mods` is not a one-off image for a single extension. It is a small platform for shipping custom PostgreSQL extensions while staying as close as possible to upstream Supabase Postgres — similar in spirit to a package repository or a Homebrew tap.

**Base image (pinned):** `supabase/postgres:17.6.1.143` (track `Dockerfile.17`)  
**Published image:** [`mewisme/supabase-mods`](https://hub.docker.com/r/mewisme/supabase-mods)  
**Architectures:** `linux/amd64`, `linux/arm64`

---

## Why this exists

Supabase Postgres ships many extensions, but not every useful extension. Native PostgreSQL extensions are ABI-sensitive: they must be compiled against the same PostgreSQL build (and libc) as the server.

Self-hosters who need extras (starting with `pg_uuidv7`) should not reinvent fragile Dockerfiles per extension. This repo provides:

- a reusable extension package layout
- ABI-safe builds against the exact upstream image
- per-major Docker tracks (`Dockerfile.17`, future `Dockerfile.18`)
- automated tests and multi-arch CI/CD
- explicit Supabase/`supautils` compatibility handling

## Goals

| Goal | How |
| --- | --- |
| Production-ready | Multi-stage images, healthchecks, fail-fast tests, pinned deps |
| Deterministic / reproducible | Pinned base tag, pinned extension sources + SHA256 |
| Modular / scalable | One directory per extension; Docker discovers enabled packages |
| Secure | Minimal runtime surface, verified downloads, no floating tags |
| Compatible | Preserve upstream entrypoint/CMD/USER; append to `supautils` allowlists |

## Relationship with upstream Supabase

- We **layer on** `supabase/postgres:17.6.1.143`; we do not fork Postgres.
- We do **not** redefine `ENTRYPOINT`, `CMD`, or `USER`.
- Hosted Supabase Cloud will **not** include these mods — this image is for self-hosted / custom deployments.
- Extension create privileges follow Supabase’s [`supautils`](https://github.com/supabase/supautils) model (`supautils.privileged_extensions`).

See [docs/architecture.md](docs/architecture.md) for ABI and Nix path details.

## Supported versions

| Component | Version |
| --- | --- |
| Major track | `17` ([`Dockerfile.17`](Dockerfile.17)) |
| Supabase Postgres image | `17.6.1.143` ([`versions/17.env`](versions/17.env)) |
| PostgreSQL | 17.6 (as shipped by upstream) |
| First bundled extension | `pg_uuidv7` 1.7.0 |

Shared defaults: [`versions.env`](versions.env). Per-major pins: `versions/<MAJOR>.env`. Never use `latest` or `*-multigres` as the **base** image.

### Adding PostgreSQL 18 later

When Supabase ships a PG18 image:

1. Add `Dockerfile.18` (copy from `.17`, adjust pins / `postgresql-server-dev-18`)
2. Add `versions/18.env` with the new Supabase pin
3. Optionally set `DEFAULT_MAJOR=18` in `versions.env` for local/PR defaults
4. CI auto-discovers the new file; `latest` moves to **18** (highest major)

## Bundled extensions

| Extension | Version | Source | Privileged |
| --- | --- | --- | --- |
| [pg_uuidv7](https://github.com/fboulnois/pg_uuidv7) | 1.7.0 | GitHub release tag (source tarball + SHA256) | yes |

License note: `pg_uuidv7` is MPL-2.0; this repository is MIT.

## Quick start

### Docker Hub

```bash
docker pull mewisme/supabase-mods:17          # floating major
docker pull mewisme/supabase-mods:17.6.1.143  # exact pin
docker run --name db -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d mewisme/supabase-mods:17
```

Connect as the upstream bootstrap user (default `supabase_admin`):

```bash
docker exec -it db psql -U supabase_admin -d postgres
```

```sql
CREATE EXTENSION pg_uuidv7;
SELECT uuid_generate_v7();
```

### Docker Compose (local)

```bash
cp .env.example .env
# POSTGRES_MAJOR=17 selects Dockerfile.17
# Optional: POSTGRES_DATABASES=app,analytics
docker compose up -d
```

- Port: `5432` (configurable via `POSTGRES_PORT`)
- Volume: persistent `pgdata`
- Healthcheck: `pg_isready -U postgres -h localhost`
- Multiple databases (first init / empty `pgdata` only):
  - Env: `POSTGRES_DATABASES=app,analytics`
  - Or SQL: add `scripts/compose/sql/*.sql` with `CREATE DATABASE ...;`  
    (see `scripts/compose/sql/01-databases.sql.example`)
  - Recreate: `docker compose down -v && docker compose up -d`

### Image tags

| Tag | Meaning |
| --- | --- |
| `17` | Floating major track |
| `17.6.1.143` | Exact upstream pin |
| `17.6.1.143-uuidv7` | Extension-flavored alias |
| `17-b<N>` | Auto-increasing build id (`github.run_number`) for major 17 |
| `latest` | Highest major track on `main` (today `17`; becomes `18` when `Dockerfile.18` exists) |
| `vX.Y.Z` | Git version tags (applied to the highest major) |

## Enabling extensions

Extensions are **available** in the image; they are not auto-created (keeps behavior close to upstream).

```sql
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;
```

Non-superuser roles that rely on Supabase’s privileged-extension path can create allowlisted extensions because install registers them in `supautils.privileged_extensions`.

## Architecture (short)

```text
Dockerfile.17 + versions/17.env   # per-major track
Dockerfile.18 + versions/18.env   # future

extensions/<name>/
  metadata.env   # pins, enable flag, privileged flag
  build.sh       # download, verify, compile -> $STAGING_DIR
  install.sh     # install artifacts into the runtime image

scripts/
  discover.sh / discover-majors.sh / build-all.sh / install-all.sh
```

Multi-stage Docker build (`Dockerfile.17`):

1. **abi** — pinned Supabase image (export server headers)
2. **builder** — `postgres:17.6-bookworm` (glibc) compile with PGXS + upstream headers
3. **runtime** — same Supabase tag; copy only staged `.so` / control / SQL; register privileged extensions

> Supabase’s Alpine image runs **glibc** Postgres (Nix). Musl-built extensions will not load.

Shared libraries are installed under `/opt/supabase-mods/lib` with absolute `module_pathname` in `.control` files so we never depend on writing into an immutable Nix store `$libdir`.

## Local development

```bash
# Static checks
bash scripts/validate.sh

# Full build + extension tests (requires Docker)
bash scripts/test.sh
```

Tests verify: image build, healthy start, `CREATE EXTENSION`, idempotency, UUID format/version/uniqueness/ordering, restart survival, and absence of unexpected FATAL/PANIC logs.

## CI/CD

GitHub Actions (`.github/workflows/docker.yml`):

- Discovers `Dockerfile.[0-9]+` majors automatically
- Triggers: `push`, `pull_request`, `workflow_dispatch`, version tags `v*`
- PRs: validate + build/test **default major** only
- `main` / tags: build all majors, multi-arch publish
- Tags: `N`, pin, `N-b<run>`, `latest` (max major on main)

## Release strategy

1. Land changes on `main` → tags `17`, `17.6.1.143`, `17-b*`, `latest`.
2. Cut a git tag `vX.Y.Z` for a versioned release (highest major).
3. Bump pins in `versions/17.env` when upstream releases a new 17.x image.

## Upgrade strategy

1. Update `versions/<MAJOR>.env` (and extension `metadata.env` as needed).
2. Rebuild and run `scripts/test.sh`.
3. Deploy a pin or `N-b*` tag; run `ALTER EXTENSION ... UPDATE` only when the extension SQL version changes.

## Compatibility guarantees

- **Same major/minor Postgres family** as the pinned Supabase image for that track.
- **Behavioral compatibility:** upstream entrypoint, config layout, and default roles are preserved.
- **Not guaranteed:** bit-identical image layers to upstream; hosted Supabase feature parity; extensions compiled against other Postgres images.

## Adding a new extension

See [docs/adding-extensions.md](docs/adding-extensions.md). In short: add `extensions/<name>/{metadata.env,build.sh,install.sh}` with `EXT_ENABLED=true`. No Dockerfile edits for new extensions (only for new **majors**).

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `libc.musl-... cannot open shared object` | Extension built with Alpine/musl gcc | Must use the glibc builder stage (`postgres:17.6-bookworm`) |
| `extension ... is not available` | Control file not in `SHAREDIR/extension` | Rebuild; check install wrote into the Nix profile share path |
| `could not access file "$libdir/..."` | `.so` not loadable from Nix pkglibdir | Confirm absolute `module_pathname` under `/opt/supabase-mods/lib` |
| `permission denied to create extension` | Not allowlisted / not superuser | Ensure `PRIVILEGED=true` and reinstall; or connect as `supabase_admin` |
| ABI / crash on `CREATE EXTENSION` | Built against wrong Postgres/libc | Use pinned Supabase runtime + glibc builder + upstream headers |
| Compose can't find Dockerfile | Wrong `POSTGRES_MAJOR` | Set `POSTGRES_MAJOR=17` to match `Dockerfile.17` |

## Roadmap

- `Dockerfile.18` when Supabase ships PG18
- Additional C extensions
- Optional pgrx/Rust extension template
- SBOM / image signing
- Dependabot-style pin update PRs for upstream image tags

## Development workflow

1. Read [docs/architecture.md](docs/architecture.md).
2. Add or change an extension package under `extensions/`.
3. `bash scripts/validate.sh && bash scripts/test.sh`.
4. Open a PR; CI must pass before merge.

## License

MIT for this project. Bundled third-party extensions retain their own licenses (see each `metadata.env`).
