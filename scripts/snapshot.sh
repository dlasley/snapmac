#!/usr/bin/env bash
#
# snapshot.sh — Evaluate installed software and generate a restore script.
#
# Usage: bash scripts/snapshot.sh [--version=exact] [--push]
#
#   --version=exact   Pin all packages to the exact versions currently installed.
#                     Default behavior installs latest versions.
#   --push            After snapshotting, commit and push to the remote repo.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

PIN_VERSIONS=false
PUSH=false
for arg in "$@"; do
    case "$arg" in
        --version=exact) PIN_VERSIONS=true ;;
        --push)          PUSH=true ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: bash scripts/snapshot.sh [--version=exact] [--push]"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Ensure brew is on PATH (required when running from cron)
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
SNAPSHOT_DIR="$PROJECT_DIR/snapshots/$TIMESTAMP"

mkdir -p "$SNAPSHOT_DIR"

RESTORE="$SNAPSHOT_DIR/restore.sh"

# ---------------------------------------------------------------------------
# Helpers (shared with all modules via sourcing)
# ---------------------------------------------------------------------------

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m==> WARNING:\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$1"; }

has() { command -v "$1" &>/dev/null; }

# Emit a standard install function into the restore script.
#
# Usage: emit_install_section func_name display_name install_cmd ver_sep packages_versioned
#   func_name          — bash function name in restore.sh (e.g. install_npm_globals)
#   display_name       — human label (e.g. "npm globals")
#   install_cmd        — command to run per package (e.g. "npm install -g")
#   ver_sep            — separator for version pinning (e.g. "@" gives name@ver, "==" gives name==ver)
#   packages_versioned — newline-separated "name version" pairs
emit_install_section() {
    local func_name="$1" display_name="$2" install_cmd="$3" ver_sep="$4" packages_versioned="$5"

    cat >> "$RESTORE" << EOF
${func_name}() {
    info "Installing ${display_name}..."
    local packages=(
EOF

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name version
        name="$(echo "$line" | awk '{print $1}')"
        version="$(echo "$line" | awk '{print $2}')"
        if [[ "$PIN_VERSIONS" == true ]]; then
            printf '        "%s%s%s"\n' "$name" "$ver_sep" "$version" >> "$RESTORE"
        else
            printf '        "%s"  # %s\n' "$name" "$version" >> "$RESTORE"
        fi
    done <<< "$packages_versioned"

    cat >> "$RESTORE" << EOF
    )
    local total=\${#packages[@]}
    local i=0
    for p in "\${packages[@]}"; do
        ((i++)) || true
        info "  [\$i/\$total] \$p"
        install_or_warn ${install_cmd} "\$p"
    done
    ok "${display_name} done (\$total packages)"
}

EOF
}

# Emit a stub function when nothing was found or tool is missing.
emit_stub_section() {
    local func_name="$1" message="$2"
    cat >> "$RESTORE" << EOF
${func_name}() {
    info "${message}"
}

EOF
}

# Scan a package manager and emit an install section.
#
# Usage: scan_and_emit func_name display_name detect_cmd install_cmd ver_sep list_cmd...
scan_and_emit() {
    local func_name="$1" display_name="$2" detect_cmd="$3" install_cmd="$4" ver_sep="$5"
    shift 5
    local list_cmd="$*"

    info "Scanning ${display_name}..."
    if has "$detect_cmd"; then
        local pkgs
        pkgs="$(eval "$list_cmd" 2>/dev/null || true)"
        if [[ -n "$pkgs" ]]; then
            local valid_pkgs="" bad_lines=0
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local fields
                fields="$(echo "$line" | awk '{print NF}')"
                if [[ "$fields" -ge 2 ]]; then
                    valid_pkgs+="$line"$'\n'
                else
                    ((bad_lines++)) || true
                fi
            done <<< "$pkgs"
            valid_pkgs="$(echo "$valid_pkgs" | sed '/^$/d')"

            if [[ $bad_lines -gt 0 ]]; then
                warn "${display_name}: skipped $bad_lines line(s) with unexpected format (expected: name version)"
            fi

            if [[ -n "$valid_pkgs" ]]; then
                local count
                count="$(echo "$valid_pkgs" | wc -l | tr -d ' ')"
                ok "Found $count ${display_name}"
                emit_install_section "$func_name" "$display_name" "$install_cmd" "$ver_sep" "$valid_pkgs"
            else
                warn "${display_name}: command produced output but no valid name/version pairs — format may have changed"
                emit_stub_section "$func_name" "No ${display_name} were captured (output format unrecognized)"
            fi
        else
            ok "No ${display_name} found"
            emit_stub_section "$func_name" "No ${display_name} were captured in this snapshot"
        fi
    else
        warn "${detect_cmd} not found — skipping ${display_name}"
        emit_stub_section "$func_name" "No ${display_name} were captured (${detect_cmd} was not installed at snapshot time)"
    fi
}

# ---------------------------------------------------------------------------
# Ensure prerequisite tools are installed on the snapshot machine
# ---------------------------------------------------------------------------

ensure_prerequisites() {
    if ! has brew; then
        warn "Homebrew is not installed — cannot install prerequisites"
        warn "Install Homebrew first: https://brew.sh"
        return
    fi

    local tools=(mas pipx)
    local tool
    for tool in "${tools[@]}"; do
        if ! has "$tool"; then
            info "Installing $tool (needed for a complete snapshot)..."
            brew install "$tool"
            ok "$tool installed"
        fi
    done

    if has pipx; then
        pipx ensurepath &>/dev/null || true
    fi
}

ensure_prerequisites

# ---------------------------------------------------------------------------
# Begin snapshot
# ---------------------------------------------------------------------------

info "Snapshot started — $TIMESTAMP"
if [[ "$PIN_VERSIONS" == true ]]; then
    info "Mode: exact versions"
else
    info "Mode: latest versions (default)"
fi
info "Output directory: $SNAPSHOT_DIR"

# ---------------------------------------------------------------------------
# Write restore.sh header
# ---------------------------------------------------------------------------

cat > "$RESTORE" << 'HEADER'
#!/usr/bin/env bash
#
# restore.sh — Reinstall software from a snapmac snapshot.
#
# Generated by snapshot.sh — do not edit by hand.
#
# Usage: bash restore.sh
#

set -uo pipefail

FAILURES=0

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m==> WARNING:\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$1"; }
err()   { printf "\033[1;31m==> ERROR:\033[0m %s\n" "$1"; }

has() { command -v "$1" &>/dev/null; }

RESTORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_or_warn() {
    local cmd="$1"; shift
    if $cmd "$@" 2>&1; then
        ok "  Installed: $*"
    else
        err "  Failed: $*"
        ((FAILURES++)) || true
    fi
}

HEADER

# ---------------------------------------------------------------------------
# Source and run modules
# Each module appends its restore function names to RESTORE_MAIN_CALLS.
# ---------------------------------------------------------------------------

RESTORE_MAIN_CALLS=()

MODULES_DIR="$SCRIPT_DIR/modules"

source "$MODULES_DIR/brew.sh"
source "$MODULES_DIR/editors.sh"
source "$MODULES_DIR/package-managers.sh"
source "$MODULES_DIR/data-science.sh"
source "$MODULES_DIR/audio.sh"
source "$MODULES_DIR/creative.sh"
source "$MODULES_DIR/browsers.sh"
source "$MODULES_DIR/terminal.sh"
source "$MODULES_DIR/unmanaged.sh"

snapshot_brew
snapshot_editors
snapshot_package_managers
snapshot_data_science
snapshot_audio
snapshot_creative
snapshot_browsers
snapshot_terminal
snapshot_unmanaged

# ---------------------------------------------------------------------------
# Write main() block from accumulated restore calls
# ---------------------------------------------------------------------------

cat >> "$RESTORE" << 'MAIN_OPEN'
# =========================================================================
# Main
# =========================================================================

main() {
    echo ""
    info "=== SnapMac Restore ==="
    echo ""

MAIN_OPEN

for fn in "${RESTORE_MAIN_CALLS[@]}"; do
    printf '    %s\n    echo ""\n' "$fn" >> "$RESTORE"
done

cat >> "$RESTORE" << 'MAIN_CLOSE'
    if [[ $FAILURES -gt 0 ]]; then
        warn "Restore completed with $FAILURES failure(s). Review output above."
    else
        ok "Restore completed successfully!"
    fi
}

main "$@"
MAIN_CLOSE

chmod +x "$RESTORE"

echo ""
ok "Snapshot complete!"
ok "Restore script: $RESTORE"
ok "Run it on a new machine with: bash $RESTORE"

if [[ "$PUSH" == true ]]; then
    echo ""
    bash "$SCRIPT_DIR/push-snapshot.sh" "$SNAPSHOT_DIR"
fi
