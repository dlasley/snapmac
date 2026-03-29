# modules/terminal.sh — Terminal emulator configuration capture.
#
# Covers: iTerm2 profiles
#
# Not covered (and why):
#   Terminal.app  — built-in; profiles stored in com.apple.Terminal plist but
#                   most users customize iTerm2 instead
#   Warp          — profile/theme config is account-synced
#   Alacritty     — config is a dotfile (~/.config/alacritty/); out of scope for snapmac
#
# Requires: $RESTORE, info(), ok(), emit_stub_section()

snapshot_terminal() {
    # ---------------------------------------------------------------------------
    # iTerm2 profiles
    # ---------------------------------------------------------------------------

    info "Scanning iTerm2 profiles..."
    local ITERM2_PROFILES
    ITERM2_PROFILES="$(python3 -c "
import subprocess, plistlib, sys
try:
    result = subprocess.run(['defaults', 'export', 'com.googlecode.iterm2', '-'], capture_output=True)
    if result.returncode != 0:
        sys.exit(0)
    prefs = plistlib.loads(result.stdout)
    for p in prefs.get('New Bookmarks', []):
        print(p.get('Name', 'Unnamed Profile'))
except: pass
" 2>/dev/null || true)"

    if [[ -n "$ITERM2_PROFILES" ]]; then
        local ITERM2_COUNT
        ITERM2_COUNT="$(echo "$ITERM2_PROFILES" | wc -l | tr -d ' ')"
        ok "Found $ITERM2_COUNT iTerm2 profiles"

        cat >> "$RESTORE" << 'EOF'
review_iterm2_profiles() {
    info "The following iTerm2 profiles were configured at snapshot time."
    info "Recreate via iTerm2 → Preferences → Profiles, or restore from a backup:"
    echo ""
    local profiles=(
EOF
        local profile
        while IFS= read -r profile; do
            [[ -n "$profile" ]] && printf '        "%s"\n' "$profile" >> "$RESTORE"
        done <<< "$ITERM2_PROFILES"
        cat >> "$RESTORE" << 'EOF'
    )
    for p in "${profiles[@]}"; do
        echo "  - $p"
    done
    echo ""
}

EOF
    else
        info "No iTerm2 profiles found (iTerm2 may not be installed)"
        emit_stub_section "review_iterm2_profiles" "No iTerm2 profiles were captured in this snapshot"
    fi

    RESTORE_MAIN_CALLS+=(review_iterm2_profiles)
}
