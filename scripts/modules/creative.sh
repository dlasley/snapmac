# modules/creative.sh — Creative application plugin/addon capture.
#
# Covers: Blender addons
#
# Not covered (and why):
#   Figma       — plugins are account-synced; nothing to capture locally
#   Adobe CC    — plugins installed via Creative Cloud desktop app; no CLI
#   Affinity    — no plugin system
#   Procreate   — iOS/iPadOS only
#
# Requires: $RESTORE, info(), ok(), emit_stub_section()

snapshot_creative() {
    # ---------------------------------------------------------------------------
    # Blender addons
    # ---------------------------------------------------------------------------

    info "Scanning Blender addons..."
    local BLENDER_BASE="$HOME/Library/Application Support/Blender"

    if [[ -d "$BLENDER_BASE" ]]; then
        local BLENDER_ADDONS
        BLENDER_ADDONS="$(find "$BLENDER_BASE" -path "*/scripts/addons" -type d -maxdepth 5 2>/dev/null \
            | while read -r addons_dir; do
                ls -1 "$addons_dir" 2>/dev/null | grep -v '^__pycache__$'
              done | sort -u || true)"

        if [[ -n "$BLENDER_ADDONS" ]]; then
            local BLENDER_COUNT
            BLENDER_COUNT="$(echo "$BLENDER_ADDONS" | wc -l | tr -d ' ')"
            ok "Found $BLENDER_COUNT Blender addons"

            cat >> "$RESTORE" << 'EOF'
review_blender_addons() {
    info "The following Blender addons were installed at snapshot time."
    info "Reinstall via Edit → Preferences → Add-ons → Install:"
    echo ""
    local addons=(
EOF
            local addon
            while IFS= read -r addon; do
                [[ -n "$addon" ]] && printf '        "%s"\n' "$addon" >> "$RESTORE"
            done <<< "$BLENDER_ADDONS"
            cat >> "$RESTORE" << 'EOF'
    )
    for a in "${addons[@]}"; do
        echo "  - $a"
    done
    echo ""
}

EOF
        else
            ok "No user-installed Blender addons found"
            emit_stub_section "review_blender_addons" "No Blender addons were captured in this snapshot"
        fi
    else
        info "Blender not found — skipping addons"
        emit_stub_section "review_blender_addons" "No Blender addons were captured (Blender was not installed at snapshot time)"
    fi

    RESTORE_MAIN_CALLS+=(review_blender_addons)
}
