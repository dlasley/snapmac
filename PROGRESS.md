# Progress Tracker

## Current Branch
`main`

## Last Session Summary
**Date**: 2026-03-27

### Completed Work (this session)
- Modularized snapshot.sh into `scripts/modules/`: brew, editors, package-managers, data-science, audio, creative, browsers, terminal, unmanaged
- snapshot.sh is now a thin orchestrator; each module exposes a `snapshot_<name>()` function and appends to `RESTORE_MAIN_CALLS[]`
- R packages moved to data-science module (with Jupyter kernels)
- Coverage notes documented in module comments and memory

### Completed Work (prior)
- Created `scripts/snapshot.sh` with full package manager support and `--version=exact` flag
- Integrated `brew bundle` for Brewfile generation; `restore.sh` handles Xcode CLT + Homebrew from scratch
- Created GitHub repo: https://github.com/dlasley/snapmac (public)
- Created private snapshot storage repo: https://github.com/dlasley/snapmac-snapshots
- Added `.env` / `.env.example` with `SNAPMAC_REMOTE_REPO` and `SNAPMAC_PIN_VERSIONS`
- `push-snapshot.sh` sources `.env` and auto-configures git remote on first run
- Fixed `push-snapshot.sh` to treat `snapshots/` as an independent git repo (separate from snapmac)
- Merged `auto-snapshot.sh` into `snapshot.sh` via `--push` flag; deleted `auto-snapshot.sh`
- `setup-cron.sh` now registers `snapshot.sh --push` with logging to `snapshots/auto-snapshot.log`
- Crontab configured: every 3 hours with `--push`
- First snapshot generated locally; push tested via `push-snapshot.sh`
- Added README

## Uncommitted Changes
- None

## Pending Items
- [ ] Add plugin/extension capture for: **Obsidian** (community plugin IDs in `~/.obsidian/community-plugins.json`, restorable), **Zed** (`zed --install-extension`, similar to Cursor), **Alfred** (workflows capturable, no restore CLI — review list only), **Arc** (Chromium-based, different profile path from Chrome)

- [ ] Decide on `SNAPMAC_PIN_VERSIONS` — wire it up in `snapshot.sh` or drop it
- [ ] Test `restore.sh` end-to-end on a clean macOS install or VM
- [ ] Consider snapshotting macOS system preferences via `defaults`
- [ ] Change push strategy: overwrite static `restore.sh` + `Brewfile` at root of `snapmac-snapshots` instead of pushing timestamped dirs. Keeps remote repo tiny forever (git stores diffs). Local timestamped dirs can remain for local history. Update `push-snapshot.sh` to copy latest snapshot files to repo root and force-push.
- [ ] Pluggable storage backends: abstract push layer so users can push snapshots to GitHub, S3, GDrive, Dropbox, Azure, FTP, etc. Plan: keep `snapshot.sh` in bash; rewrite push layer in Python with a proper ABC that backend modules implement. Python 3 is already a de facto dependency (used inline for JSON parsing). Ship `git` and `s3` (boto3) as reference backends. Users implement a Python class for custom storage.

## Known Issues
- None currently

## Next Steps (Suggested)
1. Wire up `SNAPMAC_PIN_VERSIONS` from `.env` in `snapshot.sh`, or remove it
2. Validate `restore.sh` end-to-end on a fresh macOS install
