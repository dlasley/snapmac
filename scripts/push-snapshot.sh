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

# Load .env if present
[[ -f "$PROJECT_DIR/.env" ]] && source "$PROJECT_DIR/.env"

SNAPSHOTS_DIR="$PROJECT_DIR/snapshots"

# Determine which snapshot to push
if [[ -n "${1:-}" ]]; then
    SNAPSHOT_DIR="$1"
else
    SNAPSHOT_DIR="$(ls -td "$SNAPSHOTS_DIR"/*/ 2>/dev/null | head -1)"
fi

if [[ -z "$SNAPSHOT_DIR" || ! -d "$SNAPSHOT_DIR" ]]; then
    err "No snapshot directory found"
    exit 1
fi

SNAPSHOT_NAME="$(basename "$SNAPSHOT_DIR")"
info "Pushing snapshot: $SNAPSHOT_NAME"

# Initialize snapshots/ as its own git repo if needed
if [[ ! -d "$SNAPSHOTS_DIR/.git" ]]; then
    git -C "$SNAPSHOTS_DIR" init
    info "Initialized git repo in snapshots/"
fi

# Configure remote from .env if not already set
if ! git -C "$SNAPSHOTS_DIR" remote get-url origin &>/dev/null; then
    if [[ -n "${SNAPMAC_REMOTE_REPO:-}" ]]; then
        git -C "$SNAPSHOTS_DIR" remote add origin "$SNAPMAC_REMOTE_REPO"
        info "Remote 'origin' set to $SNAPMAC_REMOTE_REPO"
    else
        err "No git remote 'origin' configured"
        err "Set SNAPMAC_REMOTE_REPO in .env or run: git remote add origin <your-repo-url>"
        exit 1
    fi
fi

# Stage, commit, push
git -C "$SNAPSHOTS_DIR" add "$SNAPSHOT_NAME"
if git -C "$SNAPSHOTS_DIR" diff --cached --quiet; then
    ok "No new changes to push"
    exit 0
fi

git -C "$SNAPSHOTS_DIR" commit -m "snapshot: $SNAPSHOT_NAME"
git -C "$SNAPSHOTS_DIR" push origin HEAD

ok "Snapshot $SNAPSHOT_NAME pushed to remote"
