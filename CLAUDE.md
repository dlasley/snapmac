# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SnapMac is a macOS system snapshot and restoration tool written in Bash. It scans the current system's installed software and generates a `restore.sh` script and `Brewfile` that can rebuild the same environment on a fresh macOS installation.

## Running the Scripts

```bash
# Generate a snapshot (installs latest versions when restoring)
bash scripts/snapshot.sh

# Generate a snapshot with exact version pinning
bash scripts/snapshot.sh --version=exact

# Run snapshot + push to remote git (cron-friendly)
bash scripts/auto-snapshot.sh

# Set up a cron job for auto-snapshots
bash scripts/setup-cron.sh

# Push an existing snapshot to remote git
bash scripts/push-snapshot.sh
```

Generated snapshots land in `snapshots/<YYYY-MM-DD_HHMMSS>/` containing `restore.sh` and `Brewfile`. The `snapshots/` directory is gitignored.

## Architecture

### Script Roles

- **snapshot.sh** — Core engine. Scans all package managers, detects unmanaged binaries/apps, and writes `restore.sh` + `Brewfile` to a timestamped directory.
- **auto-snapshot.sh** — Thin wrapper that calls `snapshot.sh` then `push-snapshot.sh`; designed for unattended cron execution.
- **push-snapshot.sh** — Commits and pushes the latest snapshot directory to a remote git repo.
- **setup-cron.sh** — Interactive helper that registers `auto-snapshot.sh` in the user's crontab.

### How snapshot.sh Generates restore.sh

1. **Brewfile** is created first via `brew bundle dump --force`, capturing Homebrew formulae, casks, Mac App Store apps, and VS Code extensions.
2. For each additional package manager (npm, pip3, pipx, uv, pnpm, yarn, Deno, Bun, mise, Go, Cargo, Ruby gems, Composer), `snapshot.sh` calls `emit_install_section()` which writes a self-contained bash function into `restore.sh`.
3. **Unmanaged detection**: binaries in `$PATH` not owned by any known package manager are listed as manual warnings; GUI apps in `/Applications` not from Homebrew/App Store are similarly flagged.
4. The `--version=exact` flag changes how `emit_install_section()` formats package entries — it injects the `ver_sep` character (e.g. `@`, `==`) between name and version rather than leaving version as a comment.

### Key Patterns in snapshot.sh

- `set -euo pipefail` throughout — all scripts fail fast on errors.
- `has <cmd>` helper checks if a command exists before trying to use it.
- `emit_install_section func_name display_name install_cmd ver_sep packages_versioned` — the central abstraction for writing per-package-manager restore functions.
- Logging uses `info()` (blue), `warn()` (yellow), `ok()` (green) for color-coded output.
- Python 3 is used inline for JSON parsing where shell tools fall short.

## Shell Script Conventions

- Use `#!/usr/bin/env bash` shebang and `set -euo pipefail` in all scripts.
- Follow the existing `info` / `warn` / `ok` / `err` logging pattern.
- Check for tool availability with `has <cmd>` before use; skip or warn gracefully when missing.
- Write to `$RESTORE` via `cat >> "$RESTORE" << EOF` heredocs or `printf ... >> "$RESTORE"`.
- Temp files should be cleaned up with a `trap` on EXIT.
