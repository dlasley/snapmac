# Progress Tracker

## Current Branch
`main`

## Last Session Summary
**Date**: 2026-03-27

### Completed Work
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
- [ ] Decide on `SNAPMAC_PIN_VERSIONS` — wire it up in `snapshot.sh` or drop it
- [ ] Test `restore.sh` end-to-end on a clean macOS install or VM
- [ ] Consider snapshotting macOS system preferences via `defaults`
- [ ] Change push strategy: overwrite static `restore.sh` + `Brewfile` at root of `snapmac-snapshots` instead of pushing timestamped dirs. Keeps remote repo tiny forever (git stores diffs). Local timestamped dirs can remain for local history. Update `push-snapshot.sh` to copy latest snapshot files to repo root and force-push.

## Known Issues
- None currently

## Next Steps (Suggested)
1. Wire up `SNAPMAC_PIN_VERSIONS` from `.env` in `snapshot.sh`, or remove it
2. Validate `restore.sh` end-to-end on a fresh macOS install
