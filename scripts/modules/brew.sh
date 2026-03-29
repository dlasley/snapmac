# modules/brew.sh — Homebrew Brewfile generation and restore functions.
#
# Requires: $RESTORE, $SNAPSHOT_DIR, info(), warn(), ok()

snapshot_brew() {
    # ---------------------------------------------------------------------------
    # Generate Brewfile
    # ---------------------------------------------------------------------------

    local BREWFILE="$SNAPSHOT_DIR/Brewfile"
    if has brew; then
        info "Generating Brewfile via brew bundle..."
        brew bundle dump --file="$BREWFILE" --describe --force 2>/dev/null
        local BREWFILE_LINES
        BREWFILE_LINES="$(wc -l < "$BREWFILE" | tr -d ' ')"
        ok "Brewfile generated ($BREWFILE_LINES entries)"
    else
        warn "brew not found — skipping Brewfile generation"
    fi

    # ---------------------------------------------------------------------------
    # Emit restore functions
    # ---------------------------------------------------------------------------

    cat >> "$RESTORE" << 'EOF'
# =========================================================================
# Prerequisites
# =========================================================================

ensure_xcode_clt() {
    info "Checking Xcode Command Line Tools..."
    if xcode-select -p &>/dev/null; then
        ok "Xcode CLT already installed"
        return
    fi

    info "Installing Xcode Command Line Tools (required for Homebrew, git, and other tools)..."
    info "A dialog will appear — click 'Install' and 'Agree' to proceed."
    xcode-select --install 2>/dev/null

    until xcode-select -p &>/dev/null; do
        sleep 5
    done
    ok "Xcode CLT installed"
}

# =========================================================================
# Homebrew
# =========================================================================

install_homebrew() {
    info "Checking Homebrew..."
    if has brew; then
        ok "Homebrew already installed"
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        ok "Homebrew installed"
    fi
}

install_from_brewfile() {
    local brewfile="$RESTORE_DIR/Brewfile"
    if [[ ! -f "$brewfile" ]]; then
        err "Brewfile not found at $brewfile"
        err "Ensure the Brewfile is in the same directory as this restore script."
        ((FAILURES++)) || true
        return
    fi
    info "Installing from Brewfile (formulae, casks, App Store apps, VS Code extensions)..."
    if brew bundle --file="$brewfile" --verbose 2>&1; then
        ok "Brewfile installation complete"
    else
        warn "Some Brewfile entries failed — review output above"
        ((FAILURES++)) || true
    fi
}

EOF

    RESTORE_MAIN_CALLS+=(ensure_xcode_clt install_homebrew install_from_brewfile)
}
