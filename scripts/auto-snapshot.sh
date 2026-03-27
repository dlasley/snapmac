#!/usr/bin/env bash
#
# auto-snapshot.sh — Run a snapshot and push to remote. Designed for crontab.
#
# Usage: bash scripts/auto-snapshot.sh
#
# Logs output to snapshots/auto-snapshot.log
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG="$PROJECT_DIR/snapshots/auto-snapshot.log"

mkdir -p "$PROJECT_DIR/snapshots"

# Redirect all output to log (and stdout if running interactively)
if [[ -t 1 ]]; then
    exec > >(tee -a "$LOG") 2>&1
else
    exec >> "$LOG" 2>&1
fi

echo ""
echo "=========================================="
echo "Auto-snapshot: $(date)"
echo "=========================================="

# Ensure brew is on PATH (cron doesn't load shell profile)
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Run snapshot
bash "$SCRIPT_DIR/snapshot.sh"

# Push to remote
bash "$SCRIPT_DIR/push-snapshot.sh"

echo "Auto-snapshot complete: $(date)"
