# Contributing

## Prerequisites

- Docker with Buildx
- Bash (Git Bash or WSL on Windows)

## Workflow

1. Fork and branch from `main`.
2. Prefer extending `extensions/` over changing a Dockerfile.
3. Keep pins in `versions/<MAJOR>.env` / `metadata.env` — no `latest` base tags.
4. New Postgres major = `Dockerfile.N` + `versions/N.env` (CI discovers automatically).
4. All shell scripts: `set -euo pipefail`.
5. Run:

```bash
bash scripts/validate.sh
bash scripts/test.sh
```

6. Open a PR. CI must pass (validate, build, test). Images are not pushed from PRs.

## Code style

- Smallest change that works (see project ponytail rules).
- Reuse `scripts/lib.sh` helpers.
- Document non-obvious ABI/Nix decisions near the code or in `docs/architecture.md`.

## Security

- Verify downloads with SHA256.
- Do not commit secrets (`.env`).
- Do not add unnecessary packages to the runtime stage.
