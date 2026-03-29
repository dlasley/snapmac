# modules/package-managers.sh — Language/runtime package manager capture.
#
# Covers: npm, pip3, pipx, uv, pnpm, yarn, deno, bun, mise, go, cargo, ruby gems, composer
# Requires: $RESTORE, $PIN_VERSIONS, info(), warn(), ok(), scan_and_emit(), emit_stub_section()

snapshot_package_managers() {
    # ---------------------------------------------------------------------------
    # npm
    # ---------------------------------------------------------------------------

    local NPM_LIST_CMD='npm list -g --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    deps = data.get(\"dependencies\", {})
    for name, info in sorted(deps.items()):
        if name == \"npm\": continue
        print(f\"{name} {info.get(\"version\", \"unknown\")}\")
except: pass
"'
    scan_and_emit "install_npm_globals" "npm globals" "npm" "npm install -g" "@" "$NPM_LIST_CMD"

    # ---------------------------------------------------------------------------
    # pip3
    # ---------------------------------------------------------------------------

    scan_and_emit "install_pip3_packages" "pip3 user packages" "pip3" "pip3 install --user" "==" \
        "pip3 list --user --format=freeze 2>/dev/null | sed 's/==/ /'"

    # ---------------------------------------------------------------------------
    # pipx
    # ---------------------------------------------------------------------------

    scan_and_emit "install_pipx_packages" "pipx packages" "pipx" "pipx install" "==" \
        "pipx list --short 2>/dev/null"

    # ---------------------------------------------------------------------------
    # uv
    # ---------------------------------------------------------------------------

    scan_and_emit "install_uv_tools" "uv tools" "uv" "uv tool install" "==" \
        "uv tool list 2>/dev/null | grep -E '^\S' | sed 's/ v/ /'"

    # ---------------------------------------------------------------------------
    # pnpm
    # ---------------------------------------------------------------------------

    local PNPM_LIST_CMD='pnpm list -g --json --depth=0 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in (data if isinstance(data, list) else [data]):
        for name, info in item.get(\"dependencies\", {}).items():
            if name == \"pnpm\": continue
            print(f\"{name} {info.get(\"version\", \"unknown\")}\")
except: pass
"'
    scan_and_emit "install_pnpm_globals" "pnpm globals" "pnpm" "pnpm add -g" "@" "$PNPM_LIST_CMD"

    # ---------------------------------------------------------------------------
    # yarn
    # ---------------------------------------------------------------------------

    scan_and_emit "install_yarn_globals" "yarn globals" "yarn" "yarn global add" "@" \
        'yarn global list 2>/dev/null | grep "^info " | grep "@" | sed "s/^info \"//" | sed "s/\"$//" | while IFS="@" read -r n v; do [[ -n "$n" ]] && echo "$n $v"; done'

    # ---------------------------------------------------------------------------
    # deno
    # ---------------------------------------------------------------------------

    local DENO_LIST_CMD='ls -1 "$HOME/.deno/bin" 2>/dev/null | while read -r name; do
    [[ "$name" == "deno" ]] && continue
    echo "$name unknown"
done'
    scan_and_emit "install_deno_packages" "Deno packages" "deno" "deno install -g" "@" "$DENO_LIST_CMD"

    # ---------------------------------------------------------------------------
    # bun
    # ---------------------------------------------------------------------------

    local BUN_LIST_CMD='bun pm ls -g 2>/dev/null | tail -n +2 | sed "s/.*── //" | while read -r line; do
    name="${line%%@*}"
    ver="${line##*@}"
    [[ -n "$name" && "$name" != "bun" ]] && echo "$name $ver"
done'
    scan_and_emit "install_bun_globals" "Bun globals" "bun" "bun install -g" "@" "$BUN_LIST_CMD"

    # ---------------------------------------------------------------------------
    # mise
    # ---------------------------------------------------------------------------

    scan_and_emit "install_mise_tools" "mise tools" "mise" "mise install" "@" \
        'mise list --installed 2>/dev/null | awk "NR>0 && \$1 !~ /^-/ {print \$1 \" \" \$2}"'

    # ---------------------------------------------------------------------------
    # Go binaries
    # ---------------------------------------------------------------------------

    local GO_BIN_DIR="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
    local GO_LIST_CMD="find \"$GO_BIN_DIR\" -maxdepth 1 -type f -perm +111 -exec go version -m {} \\; 2>/dev/null | awk '/^\tpath/ {path=\$2} /^\tmod/ {print path \" \" \$3}'"

    if [[ -d "$GO_BIN_DIR" ]]; then
        scan_and_emit "install_go_binaries" "Go binaries" "go" "go install" "@" "$GO_LIST_CMD"
    else
        info "Scanning Go binaries..."
        if ! has go; then
            warn "go not found — skipping Go binaries"
        else
            ok "No Go bin directory found ($GO_BIN_DIR)"
        fi
        emit_stub_section "install_go_binaries" "No Go binaries were captured in this snapshot"
    fi

    # ---------------------------------------------------------------------------
    # Composer
    # ---------------------------------------------------------------------------

    local COMPOSER_LIST_CMD='composer global show --format=json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for pkg in data.get(\"installed\", []):
        print(pkg[\"name\"] + \" \" + pkg[\"version\"])
except: pass
"'
    scan_and_emit "install_composer_packages" "Composer packages" "composer" "composer global require" ":" \
        "$COMPOSER_LIST_CMD"

    # ---------------------------------------------------------------------------
    # Cargo (special: version pinning uses --version flag, not inline separator)
    # ---------------------------------------------------------------------------

    info "Scanning Cargo packages..."
    if has cargo; then
        local CARGO_PKGS
        CARGO_PKGS="$(cargo install --list 2>/dev/null | grep -E '^[a-zA-Z]' | sed 's/ v/ /' | sed 's/:$//' || true)"
        if [[ -n "$CARGO_PKGS" ]]; then
            local CARGO_COUNT
            CARGO_COUNT="$(echo "$CARGO_PKGS" | wc -l | tr -d ' ')"
            ok "Found $CARGO_COUNT Cargo packages"

            cat >> "$RESTORE" << 'CARGO_FUNC'
install_cargo_packages() {
    if ! has cargo; then
        if has rustup; then
            info "Setting up Rust toolchain via rustup..."
            rustup default stable
        else
            info "Installing Rust via rustup..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source "$HOME/.cargo/env"
        fi
    fi
    info "Installing Cargo packages..."
    local packages=(
CARGO_FUNC

            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local name version
                name="$(echo "$line" | awk '{print $1}')"
                version="$(echo "$line" | awk '{print $2}')"
                if [[ "$PIN_VERSIONS" == true ]]; then
                    printf '        "%s %s"\n' "$name" "$version" >> "$RESTORE"
                else
                    printf '        "%s"  # %s\n' "$name" "$version" >> "$RESTORE"
                fi
            done <<< "$CARGO_PKGS"

            if [[ "$PIN_VERSIONS" == true ]]; then
                cat >> "$RESTORE" << 'CARGO_FUNC'
    )
    local total=${#packages[@]}
    local i=0
    for p in "${packages[@]}"; do
        ((i++)) || true
        local pkg_name="${p%% *}"
        local pkg_ver="${p##* }"
        info "  [$i/$total] $pkg_name@$pkg_ver"
        install_or_warn cargo install "$pkg_name" --version "$pkg_ver"
    done
    ok "Cargo packages done ($total packages)"
}

CARGO_FUNC
            else
                cat >> "$RESTORE" << 'CARGO_FUNC'
    )
    local total=${#packages[@]}
    local i=0
    for p in "${packages[@]}"; do
        ((i++)) || true
        info "  [$i/$total] $p"
        install_or_warn cargo install "$p"
    done
    ok "Cargo packages done ($total packages)"
}

CARGO_FUNC
            fi
        else
            ok "No Cargo packages found"
            emit_stub_section "install_cargo_packages" "No Cargo packages were captured in this snapshot"
        fi
    else
        warn "cargo not found — skipping Cargo packages"
        emit_stub_section "install_cargo_packages" "No Cargo packages were captured (cargo was not installed at snapshot time)"
    fi

    # ---------------------------------------------------------------------------
    # Ruby gems (special: version pinning uses -v flag)
    # ---------------------------------------------------------------------------

    info "Scanning Ruby gems..."
    if has gem; then
        local GEM_PKGS
        GEM_PKGS="$(gem list --local --no-default 2>/dev/null | grep -E '^\S+ \(' | sed 's/ (/\t/' | sed 's/)$//' || true)"
        if [[ -n "$GEM_PKGS" ]]; then
            local GEM_COUNT
            GEM_COUNT="$(echo "$GEM_PKGS" | wc -l | tr -d ' ')"
            ok "Found $GEM_COUNT Ruby gems"

            cat >> "$RESTORE" << 'GEM_FUNC'
install_ruby_gems() {
    if ! has gem; then
        warn "gem not found — skipping Ruby gems"
        return
    fi
    info "Installing Ruby gems..."
    local packages=(
GEM_FUNC

            while IFS=$'\t' read -r name version; do
                [[ -z "$name" ]] && continue
                local latest_ver
                latest_ver="$(echo "$version" | awk -F', ' '{print $1}')"
                if [[ "$PIN_VERSIONS" == true ]]; then
                    printf '        "%s %s"\n' "$name" "$latest_ver" >> "$RESTORE"
                else
                    printf '        "%s"  # %s\n' "$name" "$latest_ver" >> "$RESTORE"
                fi
            done <<< "$GEM_PKGS"

            if [[ "$PIN_VERSIONS" == true ]]; then
                cat >> "$RESTORE" << 'GEM_FUNC'
    )
    local total=${#packages[@]}
    local i=0
    for p in "${packages[@]}"; do
        ((i++)) || true
        local gem_name="${p%% *}"
        local gem_ver="${p##* }"
        info "  [$i/$total] $gem_name@$gem_ver"
        install_or_warn gem install "$gem_name" -v "$gem_ver"
    done
    ok "Ruby gems done ($total packages)"
}

GEM_FUNC
            else
                cat >> "$RESTORE" << 'GEM_FUNC'
    )
    local total=${#packages[@]}
    local i=0
    for p in "${packages[@]}"; do
        ((i++)) || true
        info "  [$i/$total] $p"
        install_or_warn gem install "$p"
    done
    ok "Ruby gems done ($total packages)"
}

GEM_FUNC
            fi
        else
            ok "No non-default Ruby gems found"
            emit_stub_section "install_ruby_gems" "No Ruby gems were captured in this snapshot"
        fi
    else
        warn "gem not found — skipping Ruby gems"
        emit_stub_section "install_ruby_gems" "No Ruby gems were captured (gem was not installed at snapshot time)"
    fi

    RESTORE_MAIN_CALLS+=(
        install_npm_globals
        install_pip3_packages
        install_pipx_packages
        install_uv_tools
        install_pnpm_globals
        install_yarn_globals
        install_deno_packages
        install_bun_globals
        install_mise_tools
        install_go_binaries
        install_composer_packages
        install_cargo_packages
        install_ruby_gems
    )
}
