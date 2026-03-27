# Progress Tracker

## Current Branch
`main`

## Last Session Summary
**Date**: 2026-03-27

### Completed Work
- Created `scripts/snapshot.sh` — single script that evaluates the current system
- Generates `snapshots/<timestamp>/restore.sh` with all install commands
- Covers: Homebrew formulae & casks, Mac App Store (mas), npm globals, pip3 user packages, pipx, VS Code extensions, unmanaged CLIs
- Added `--version=exact` flag for version pinning
- Added explicit package managers: Cargo, Ruby gems, Go binaries, Composer
- Integrated `brew bundle` — generates a Brewfile alongside restore.sh
- Manual install functions retained as fallback when Brewfile is missing

## Uncommitted Changes
- `scripts/snapshot.sh` (new)
- `PROGRESS.md` (new)
- `.gitignore` (untracked)

## Pending Items
- [ ] Initial commit
- [ ] Simplify snapshot.sh — remove redundant manual brew/cask/mas/vscode sections once Brewfile path is fully validated
- [ ] Test restore.sh on a clean machine or VM

## Known Issues
- None currently

## Next Steps (Suggested)
1. Commit initial project state
2. Validate restore.sh end-to-end (ideally on a fresh macOS install or VM)
3. Once Brewfile restore is validated, simplify by removing redundant manual install code
4. Consider snapshotting macOS system preferences / defaults
