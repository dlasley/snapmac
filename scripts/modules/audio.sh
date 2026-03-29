# modules/audio.sh — Audio plugin capture (AU, VST, VST3, AAX).
#
# Scans system and user audio plugin directories for all common formats.
# Restore is manual — no standard CLI exists for audio plugin installation.
#
# Formats covered:
#   .component  — Audio Units (AU): Logic, GarageBand, and most DAWs
#   .vst        — VST2: Ableton, Cubase, Bitwig, etc.
#   .vst3       — VST3: modern standard across all DAWs
#   .aaxplugin  — AAX: Pro Tools (Avid) only; located in Avid-specific directories
#
# Notes:
#   - All formats require manual reinstall via manufacturer websites or download
#     managers (iLok, Native Instruments Access, Avid Link, Steinberg Download
#     Assistant, etc.)
#   - License reactivation (iLok, eLicenser, software serials) must be done
#     independently — cannot be scripted.
#   - DAW content libraries (samples, loops, instruments) are not captured here;
#     they are too large and must be re-downloaded via the DAW's own content manager.
#
# Requires: $RESTORE, info(), ok(), emit_stub_section()

snapshot_audio() {
    info "Scanning audio plugins (AU/VST/AAX)..."

    local AUDIO_PLUGINS=""
    local dir
    for dir in \
        "/Library/Audio/Plug-Ins/Components" \
        "$HOME/Library/Audio/Plug-Ins/Components" \
        "/Library/Audio/Plug-Ins/VST" \
        "$HOME/Library/Audio/Plug-Ins/VST" \
        "/Library/Audio/Plug-Ins/VST3" \
        "$HOME/Library/Audio/Plug-Ins/VST3" \
        "/Library/Application Support/Avid/Audio/Plug-Ins" \
        "$HOME/Documents/Avid/Audio/Plug-Ins"; do
        [[ -d "$dir" ]] || continue
        local plugin
        while IFS= read -r plugin; do
            local name type
            name="$(basename "$plugin" | sed 's/\.\(component\|vst\|vst3\|aaxplugin\)$//')"
            type="$(basename "$plugin" | grep -oE '\.(component|vst|vst3|aaxplugin)$' | tr -d '.')"
            [[ -n "$name" ]] && AUDIO_PLUGINS+="$name ($type)"$'\n'
        done < <(find "$dir" -maxdepth 1 \( -name "*.component" -o -name "*.vst" -o -name "*.vst3" -o -name "*.aaxplugin" \) 2>/dev/null)
    done
    AUDIO_PLUGINS="$(echo "$AUDIO_PLUGINS" | sort -u | sed '/^$/d')"

    if [[ -n "$AUDIO_PLUGINS" ]]; then
        local AUDIO_COUNT
        AUDIO_COUNT="$(echo "$AUDIO_PLUGINS" | wc -l | tr -d ' ')"
        ok "Found $AUDIO_COUNT audio plugins"

        cat >> "$RESTORE" << 'EOF'
review_audio_plugins() {
    info "The following AU/VST/AAX audio plugins were installed at snapshot time."
    info "Reinstall via manufacturer websites or download managers (iLok, NI Access, Avid Link, etc.):"
    echo ""
    local plugins=(
EOF
        local plugin
        while IFS= read -r plugin; do
            [[ -n "$plugin" ]] && printf '        "%s"\n' "$plugin" >> "$RESTORE"
        done <<< "$AUDIO_PLUGINS"
        cat >> "$RESTORE" << 'EOF'
    )
    for p in "${plugins[@]}"; do
        echo "  - $p"
    done
    echo ""
    warn "Audio plugin licenses must be reactivated independently."
}

EOF
    else
        ok "No audio plugins found"
        emit_stub_section "review_audio_plugins" "No audio plugins were captured in this snapshot"
    fi

    RESTORE_MAIN_CALLS+=(review_audio_plugins)
}
