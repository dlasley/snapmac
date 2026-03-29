# modules/editors.sh — IDE and editor plugin/extension capture.
#
# Covers: Sketch plugins, Cursor extensions
# Requires: $RESTORE, $PIN_VERSIONS, info(), warn(), ok(), emit_install_section(), emit_stub_section()

snapshot_editors() {
    # ---------------------------------------------------------------------------
    # Sketch plugins
    # ---------------------------------------------------------------------------

    local SKETCH_PLUGINS_DIR="$HOME/Library/Application Support/com.bohemiancoding.sketch3/Plugins"
    info "Scanning Sketch plugins..."
    if [[ -d "$SKETCH_PLUGINS_DIR" ]]; then
        local SKETCH_PLUGINS
        SKETCH_PLUGINS="$(find "$SKETCH_PLUGINS_DIR" -name "manifest.json" -maxdepth 3 2>/dev/null \
            | python3 -c "
import sys, json
for path in sys.stdin.read().splitlines():
    try:
        with open(path) as f:
            m = json.load(f)
            name = m.get('name', '')
            ident = m.get('identifier', '')
            if name:
                print(f'{name}|{ident}')
    except: pass
" 2>/dev/null | sort -u || true)"

        if [[ -n "$SKETCH_PLUGINS" ]]; then
            local SKETCH_COUNT
            SKETCH_COUNT="$(echo "$SKETCH_PLUGINS" | wc -l | tr -d ' ')"
            ok "Found $SKETCH_COUNT Sketch plugins"

            cat >> "$RESTORE" << 'EOF'
review_sketch_plugins() {
    info "The following Sketch plugins were installed at snapshot time."
    info "Reinstall them via Sketch → Plugins → Browse Plugins or from the plugin's source:"
    echo ""
    local plugins=(
EOF
            while IFS='|' read -r name ident; do
                [[ -z "$name" ]] && continue
                if [[ -n "$ident" ]]; then
                    printf '        "%s (%s)"\n' "$name" "$ident" >> "$RESTORE"
                else
                    printf '        "%s"\n' "$name" >> "$RESTORE"
                fi
            done <<< "$SKETCH_PLUGINS"

            cat >> "$RESTORE" << 'EOF'
    )
    for p in "${plugins[@]}"; do
        echo "  - $p"
    done
    echo ""
}

EOF
        else
            ok "No Sketch plugins found"
            emit_stub_section "review_sketch_plugins" "No Sketch plugins were captured in this snapshot"
        fi
    else
        info "Sketch plugins directory not found — skipping"
        emit_stub_section "review_sketch_plugins" "No Sketch plugins were captured (Sketch was not installed at snapshot time)"
    fi

    RESTORE_MAIN_CALLS+=(review_sketch_plugins)

    # ---------------------------------------------------------------------------
    # Cursor extensions
    # ---------------------------------------------------------------------------

    info "Scanning Cursor extensions..."
    if has cursor; then
        local CURSOR_EXTS
        CURSOR_EXTS="$(cursor --list-extensions --show-versions 2>/dev/null | sed 's/@/ /' || true)"
        if [[ -n "$CURSOR_EXTS" ]]; then
            local CURSOR_COUNT
            CURSOR_COUNT="$(echo "$CURSOR_EXTS" | wc -l | tr -d ' ')"
            ok "Found $CURSOR_COUNT Cursor extensions"
            emit_install_section "install_cursor_extensions" "Cursor extensions" "cursor --install-extension" "@" "$CURSOR_EXTS"
        else
            ok "No Cursor extensions found"
            emit_stub_section "install_cursor_extensions" "No Cursor extensions were captured in this snapshot"
        fi
    else
        warn "cursor CLI not found — skipping Cursor extensions"
        warn "To enable: open Cursor → CMD+SHIFT+P → 'Install cursor command in PATH'"
        emit_stub_section "install_cursor_extensions" "No Cursor extensions were captured (cursor CLI was not installed at snapshot time)"
    fi

    RESTORE_MAIN_CALLS+=(install_cursor_extensions)
}
