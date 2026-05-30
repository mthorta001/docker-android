# Contributing to docker-android

Thanks for contributing! This project is a mix of **Bash scripts** (build &
runtime orchestration) and **Python** (`src/`). To keep quality high we use
automated linting, formatting and tests. Please run them before opening a PR.

## Quick start

```bash
# Install git hooks once (runs all checks automatically on every commit)
make install-hooks

# Run everything manually
make lint     # shellcheck + shfmt + flake8 + mypy
make fmt      # auto-format shell (shfmt) and Python (isort + black)
make test     # unit tests with coverage
make help     # list all available targets
```

## Tooling

| Area   | Tool                  | Purpose                              |
|--------|-----------------------|--------------------------------------|
| Shell  | `shellcheck`          | Static analysis of `*.sh` scripts    |
| Shell  | `shfmt` (`-i 4 -ci`)  | Consistent formatting                |
| Python | `flake8`              | Lint (max line length 120)           |
| Python | `mypy`                | Static type checking                 |
| Python | `black` + `isort`     | Formatting & import ordering         |

Configuration lives in `.shellcheckrc`, `setup.cfg` (flake8/pytest) and
`.pre-commit-config.yaml`.

### Installing the tools locally

```bash
# Python tools
pip install -r requirements.txt
pip install flake8 mypy black isort pre-commit

# Shell tools (macOS)
brew install shellcheck shfmt

# Shell tools (Debian/Ubuntu)
apt-get install -y shellcheck
# shfmt: see https://github.com/mvdan/sh#shfmt
```

## Conventions

- **Bash scripts** should start with `#!/bin/bash` and, where practical, use
  strict mode: `set -euo pipefail` (see `travis.sh` as a reference).
- **Python** targets the version pinned in CI and uses type annotations; keep
  `mypy` clean.
- Keep changes focused; add or update tests under `src/tests/` when changing
  behavior.

## Continuous Integration

Every push and pull request runs the **Lint** workflow
(`.github/workflows/lint.yml`), which executes the same shell and Python checks
as `make lint`. Image build workflows live alongside it under
`.github/workflows/`.
