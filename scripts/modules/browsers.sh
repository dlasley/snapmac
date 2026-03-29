# modules/browsers.sh — Browser extension capture.
#
# Covers: Chrome, Firefox
# Not covered (and why):
#   Safari      — extensions come from the Mac App Store; already captured via mas in Brewfile
#   Arc         — Chromium-based; extensions stored same as Chrome but in a different profile path
#   Brave/Edge  — Chromium-based; similar profile structures, not yet implemented
#
# Requires: $RESTORE, info(), ok(), emit_stub_section()

snapshot_browsers() {
    # ---------------------------------------------------------------------------
    # Chrome extensions
    # ---------------------------------------------------------------------------

    info "Scanning Chrome extensions..."
    local CHROME_EXTENSIONS_DIR="$HOME/Library/Application Support/Google/Chrome/Default/Extensions"

    if [[ -d "$CHROME_EXTENSIONS_DIR" ]]; then
        local CHROME_EXTS
        CHROME_EXTS="$(find "$CHROME_EXTENSIONS_DIR" -name "manifest.json" -maxdepth 2 2>/dev/null \
            | python3 -c "
import sys, json
for path in sys.stdin.read().splitlines():
    try:
        with open(path) as f:
            m = json.load(f)
            name = m.get('name', '').strip()
            if name and not name.startswith('__MSG_'):
                print(name)
    except: pass
" 2>/dev/null | sort -u || true)"

        if [[ -n "$CHROME_EXTS" ]]; then
            local CHROME_COUNT
            CHROME_COUNT="$(echo "$CHROME_EXTS" | wc -l | tr -d ' ')"
            ok "Found $CHROME_COUNT Chrome extensions"

            cat >> "$RESTORE" << 'EOF'
review_chrome_extensions() {
    info "The following Chrome extensions were installed at snapshot time."
    info "Reinstall from the Chrome Web Store (chrome.google.com/webstore):"
    echo ""
    local extensions=(
EOF
            local ext
            while IFS= read -r ext; do
                [[ -n "$ext" ]] && printf '        "%s"\n' "$ext" >> "$RESTORE"
            done <<< "$CHROME_EXTS"
            cat >> "$RESTORE" << 'EOF'
    )
    for e in "${extensions[@]}"; do
        echo "  - $e"
    done
    echo ""
}

EOF
        else
            ok "No Chrome extensions found"
            emit_stub_section "review_chrome_extensions" "No Chrome extensions were captured in this snapshot"
        fi
    else
        info "Chrome not found — skipping extensions"
        emit_stub_section "review_chrome_extensions" "No Chrome extensions were captured (Chrome was not installed at snapshot time)"
    fi

    # ---------------------------------------------------------------------------
    # Firefox extensions
    # ---------------------------------------------------------------------------

    info "Scanning Firefox extensions..."
    local FIREFOX_PROFILES_DIR="$HOME/Library/Application Support/Firefox/Profiles"

    if [[ -d "$FIREFOX_PROFILES_DIR" ]]; then
        local FF_EXT_FILE
        FF_EXT_FILE="$(find "$FIREFOX_PROFILES_DIR" -name "extensions.json" -maxdepth 2 2>/dev/null | head -1)"
        local FIREFOX_EXTS
        FIREFOX_EXTS="$(FF_EXT_FILE="$FF_EXT_FILE" python3 -c "
import json, os
path = os.environ.get('FF_EXT_FILE', '')
if not path: exit()
try:
    with open(path) as f:
        data = json.load(f)
    for addon in data.get('addons', []):
        if addon.get('type') == 'extension' and not addon.get('id','').endswith('@mozilla.org'):
            name = (addon.get('defaultLocale') or {}).get('name') or addon.get('name', '')
            if name:
                print(name)
except: pass
" 2>/dev/null | sort -u || true)"

        if [[ -n "$FIREFOX_EXTS" ]]; then
            local FIREFOX_COUNT
            FIREFOX_COUNT="$(echo "$FIREFOX_EXTS" | wc -l | tr -d ' ')"
            ok "Found $FIREFOX_COUNT Firefox extensions"

            cat >> "$RESTORE" << 'EOF'
review_firefox_extensions() {
    info "The following Firefox extensions were installed at snapshot time."
    info "Reinstall from addons.mozilla.org:"
    echo ""
    local extensions=(
EOF
            local ext
            while IFS= read -r ext; do
                [[ -n "$ext" ]] && printf '        "%s"\n' "$ext" >> "$RESTORE"
            done <<< "$FIREFOX_EXTS"
            cat >> "$RESTORE" << 'EOF'
    )
    for e in "${extensions[@]}"; do
        echo "  - $e"
    done
    echo ""
}

EOF
        else
            ok "No Firefox extensions found"
            emit_stub_section "review_firefox_extensions" "No Firefox extensions were captured in this snapshot"
        fi
    else
        info "Firefox not found — skipping extensions"
        emit_stub_section "review_firefox_extensions" "No Firefox extensions were captured (Firefox was not installed at snapshot time)"
    fi

    RESTORE_MAIN_CALLS+=(review_chrome_extensions review_firefox_extensions)
}
