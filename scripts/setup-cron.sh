#!/usr/bin/env bash
#
# setup-cron.sh — Interactively add auto-snapshot.sh to crontab.
#
# Usage: bash scripts/setup-cron.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_SNAPSHOT="$SCRIPT_DIR/auto-snapshot.sh"

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m==> WARNING:\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$1"; }
err()   { printf "\033[1;31m==> ERROR:\033[0m %s\n" "$1"; }

if [[ ! -f "$AUTO_SNAPSHOT" ]]; then
    err "auto-snapshot.sh not found at $AUTO_SNAPSHOT"
    exit 1
fi

chmod +x "$AUTO_SNAPSHOT"

echo ""
info "How many times per day should the snapshot run?"
echo ""
echo "  1  — once daily          (midnight)"
echo "  2  — every 12 hours      (00:00, 12:00)"
echo "  4  — every 6 hours       (00:00, 06:00, 12:00, 18:00)"
echo "  8  — every 3 hours       (00:00, 03:00, 06:00, ...)"
echo "  12 — every 2 hours       (00:00, 02:00, 04:00, ...)"
echo "  24 — every hour          (00:00, 01:00, 02:00, ...)"
echo ""
printf "Enter frequency [1/2/4/8/12/24]: "
read -r FREQ

case "$FREQ" in
    1)  CRON_SCHEDULE="0 0 * * *" ;;
    2)  CRON_SCHEDULE="0 0,12 * * *" ;;
    4)  CRON_SCHEDULE="0 0,6,12,18 * * *" ;;
    8)  CRON_SCHEDULE="0 0,3,6,9,12,15,18,21 * * *" ;;
    12) CRON_SCHEDULE="0 0,2,4,6,8,10,12,14,16,18,20,22 * * *" ;;
    24) CRON_SCHEDULE="0 * * * *" ;;
    *)
        err "Invalid selection: $FREQ"
        echo "Please enter one of: 1, 2, 4, 8, 12, 24"
        exit 1
        ;;
esac

CRON_CMD="$CRON_SCHEDULE bash $AUTO_SNAPSHOT"
CRON_MARKER="# snapmac auto-snapshot"
CRON_LINE="$CRON_CMD $CRON_MARKER"

echo ""
info "Cron entry:"
echo "  $CRON_LINE"
echo ""

# Check for existing entry
EXISTING_CRONTAB="$(crontab -l 2>/dev/null || true)"
if echo "$EXISTING_CRONTAB" | grep -qF "$CRON_MARKER"; then
    warn "An existing auto-snapshot cron entry was found:"
    echo "  $(echo "$EXISTING_CRONTAB" | grep -F "$CRON_MARKER")"
    echo ""
    printf "Replace it? [y/N]: "
    read -r CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        info "Cancelled — no changes made"
        exit 0
    fi
    # Remove old entry, add new one
    UPDATED="$(echo "$EXISTING_CRONTAB" | grep -vF "$CRON_MARKER")"
    printf '%s\n%s\n' "$UPDATED" "$CRON_LINE" | crontab -
else
    printf "Install this cron entry? [y/N]: "
    read -r CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        info "Cancelled — no changes made"
        exit 0
    fi
    # Append to existing crontab
    if [[ -n "$EXISTING_CRONTAB" ]]; then
        printf '%s\n%s\n' "$EXISTING_CRONTAB" "$CRON_LINE" | crontab -
    else
        echo "$CRON_LINE" | crontab -
    fi
fi

ok "Cron entry installed"
echo ""
info "Current crontab:"
crontab -l
echo ""
info "Logs will be written to: snapshots/auto-snapshot.log"
