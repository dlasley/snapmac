#!/usr/bin/env bash
#
# push-snapshot.sh — Commit and push snapshot files to the remote repository.
#
# Usage: bash scripts/push-snapshot.sh [snapshot_dir]
#
#   If snapshot_dir is not provided, pushes the most recent snapshot.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m==> WARNING:\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$1"; }
err()   { printf "\033[1;31m==> ERROR:\033[0m %s\n" "$1"; }

cd "$PROJECT_DIR"

# Determine which snapshot to push
if [[ -n "${1:-}" ]]; then
    SNAPSHOT_DIR="$1"
else
    SNAPSHOT_DIR="$(ls -td snapshots/*/ 2>/dev/null | head -1)"
fi

if [[ -z "$SNAPSHOT_DIR" || ! -d "$SNAPSHOT_DIR" ]]; then
    err "No snapshot directory found"
    exit 1
fi

SNAPSHOT_NAME="$(basename "$SNAPSHOT_DIR")"
info "Pushing snapshot: $SNAPSHOT_NAME"

# Check for remote
if ! git remote get-url origin &>/dev/null; then
    err "No git remote 'origin' configured"
    err "Add a remote with: git remote add origin <your-repo-url>"
    exit 1
fi

# Ensure snapshots are not gitignored in this repo
if git check-ignore -q "$SNAPSHOT_DIR" 2>/dev/null; then
    warn "snapshots/ is in .gitignore — remove it to push snapshots"
    warn "Edit .gitignore and remove the 'snapshots/' line, then retry"
    exit 1
fi

# Stage, commit, push
git add "$SNAPSHOT_DIR"
if git diff --cached --quiet; then
    ok "No new changes to push"
    exit 0
fi

git commit -m "snapshot: $SNAPSHOT_NAME"
git push origin HEAD

ok "Snapshot $SNAPSHOT_NAME pushed to remote"
