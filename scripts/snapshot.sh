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
# Helpers
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

# ---------------------------------------------------------------------------
# Ensure prerequisite tools are installed
# ---------------------------------------------------------------------------

ensure_prerequisites() {
    if ! has brew; then
        warn "Homebrew is not installed — cannot install prerequisites"
        warn "Install Homebrew first: https://brew.sh"
        return
    fi

    local tools=(mas pipx)
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
# Begin generating restore script
# ---------------------------------------------------------------------------

info "Snapshot started — $TIMESTAMP"
if [[ "$PIN_VERSIONS" == true ]]; then
    info "Mode: exact versions"
else
    info "Mode: latest versions (default)"
fi
info "Output directory: $SNAPSHOT_DIR"

# ---------------------------------------------------------------------------
# Generate Brewfile via brew bundle (covers brew, casks, mas, vscode)
# ---------------------------------------------------------------------------

BREWFILE="$SNAPSHOT_DIR/Brewfile"
if has brew; then
    info "Generating Brewfile via brew bundle..."
    brew bundle dump --file="$BREWFILE" --describe --force 2>/dev/null
    BREWFILE_LINES="$(wc -l < "$BREWFILE" | tr -d ' ')"
    ok "Brewfile generated ($BREWFILE_LINES entries)"
else
    warn "brew not found — skipping Brewfile generation"
fi

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
# Homebrew + Brewfile
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

    # Wait for installation to complete
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

# ---------------------------------------------------------------------------
# Standard package managers (registry-driven)
# ---------------------------------------------------------------------------

scan_and_emit() {
    local func_name="$1" display_name="$2" detect_cmd="$3" install_cmd="$4" ver_sep="$5"
    # Remaining args: the list command to eval
    shift 5
    local list_cmd="$*"

    info "Scanning ${display_name}..."
    if has "$detect_cmd"; then
        local pkgs
        pkgs="$(eval "$list_cmd" 2>/dev/null || true)"
        if [[ -n "$pkgs" ]]; then
            # Validate output: each line should be "name version" (at least two fields)
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

# npm: parse JSON to get "name version" pairs, excluding npm itself
NPM_LIST_CMD='npm list -g --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    deps = data.get(\"dependencies\", {})
    for name, info in sorted(deps.items()):
        if name == \"npm\": continue
        print(f\"{name} {info.get(\"version\", \"unknown\")}\")
except: pass
"'

scan_and_emit "install_npm_globals" "npm globals" "npm" "npm install -g" "@" \
    "$NPM_LIST_CMD"

# pip3: freeze format gives "name==version"
scan_and_emit "install_pip3_packages" "pip3 user packages" "pip3" "pip3 install --user" "==" \
    "pip3 list --user --format=freeze 2>/dev/null | sed 's/==/ /'"

# pipx: list --short gives "name version"
scan_and_emit "install_pipx_packages" "pipx packages" "pipx" "pipx install" "==" \
    "pipx list --short 2>/dev/null"

# uv: tool list output is "toolname v1.2.3" per tool (with possible extra lines indented)
scan_and_emit "install_uv_tools" "uv tools" "uv" "uv tool install" "==" \
    "uv tool list 2>/dev/null | grep -E '^\S' | sed 's/ v/ /'"

# pnpm: global packages via JSON
PNPM_LIST_CMD='pnpm list -g --json --depth=0 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for item in (data if isinstance(data, list) else [data]):
        for name, info in item.get(\"dependencies\", {}).items():
            if name == \"pnpm\": continue
            print(f\"{name} {info.get(\"version\", \"unknown\")}\")
except: pass
"'

scan_and_emit "install_pnpm_globals" "pnpm globals" "pnpm" "pnpm add -g" "@" \
    "$PNPM_LIST_CMD"

# yarn: global packages (yarn global list outputs "info pkg@ver" lines)
scan_and_emit "install_yarn_globals" "yarn globals" "yarn" "yarn global add" "@" \
    'yarn global list 2>/dev/null | grep "^info " | grep "@" | sed "s/^info \"//" | sed "s/\"$//" | while IFS="@" read -r n v; do [[ -n "$n" ]] && echo "$n $v"; done'

# deno: globally installed packages
DENO_LIST_CMD='ls -1 "$HOME/.deno/bin" 2>/dev/null | while read -r name; do
    [[ "$name" == "deno" ]] && continue
    echo "$name unknown"
done'

scan_and_emit "install_deno_packages" "Deno packages" "deno" "deno install -g" "@" \
    "$DENO_LIST_CMD"

# bun: global packages
BUN_LIST_CMD='bun pm ls -g 2>/dev/null | tail -n +2 | sed "s/.*── //" | while read -r line; do
    name="${line%%@*}"
    ver="${line##*@}"
    [[ -n "$name" && "$name" != "bun" ]] && echo "$name $ver"
done'

scan_and_emit "install_bun_globals" "Bun globals" "bun" "bun install -g" "@" \
    "$BUN_LIST_CMD"

# mise: installed tools and versions
scan_and_emit "install_mise_tools" "mise tools" "mise" "mise install" "@" \
    'mise list --installed 2>/dev/null | awk "NR>0 && \$1 !~ /^-/ {print \$1 \" \" \$2}"'

# go: scan binaries and extract module path + version
GO_BIN_DIR="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
GO_LIST_CMD="find \"$GO_BIN_DIR\" -maxdepth 1 -type f -perm +111 -exec go version -m {} \\; 2>/dev/null | awk '/^\tpath/ {path=\$2} /^\tmod/ {print path \" \" \$3}'"

if [[ -d "$GO_BIN_DIR" ]]; then
    scan_and_emit "install_go_binaries" "Go binaries" "go" "go install" "@" \
        "$GO_LIST_CMD"
else
    info "Scanning Go binaries..."
    if ! has go; then
        warn "go not found — skipping Go binaries"
    else
        ok "No Go bin directory found ($GO_BIN_DIR)"
    fi
    emit_stub_section "install_go_binaries" "No Go binaries were captured in this snapshot"
fi

# composer: JSON output
COMPOSER_LIST_CMD='composer global show --format=json 2>/dev/null | python3 -c "
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
    CARGO_PKGS="$(cargo install --list 2>/dev/null | grep -E '^[a-zA-Z]' | sed 's/ v/ /' | sed 's/:$//' || true)"
    if [[ -n "$CARGO_PKGS" ]]; then
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
    GEM_PKGS="$(gem list --local --no-default 2>/dev/null | grep -E '^\S+ \(' | sed 's/ (/\t/' | sed 's/)$//' || true)"
    if [[ -n "$GEM_PKGS" ]]; then
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

# ---------------------------------------------------------------------------
# Sketch plugins
# ---------------------------------------------------------------------------

SKETCH_PLUGINS_DIR="$HOME/Library/Application Support/com.bohemiancoding.sketch3/Plugins"
info "Scanning Sketch plugins..."
if [[ -d "$SKETCH_PLUGINS_DIR" ]]; then
    SKETCH_PLUGINS="$(find "$SKETCH_PLUGINS_DIR" -name "manifest.json" -maxdepth 3 2>/dev/null \
        | xargs python3 -c "
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

# ---------------------------------------------------------------------------
# Cursor extensions
# ---------------------------------------------------------------------------

info "Scanning Cursor extensions..."
if has cursor; then
    CURSOR_EXTS="$(cursor --list-extensions --show-versions 2>/dev/null | sed 's/@/ /' || true)"
    if [[ -n "$CURSOR_EXTS" ]]; then
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

# ---------------------------------------------------------------------------
# Standalone / unmanaged CLIs
# ---------------------------------------------------------------------------

info "Scanning for unmanaged CLIs in PATH..."

MANAGED_BINS="$(mktemp)"
trap 'rm -f "$MANAGED_BINS"' EXIT

# Collect all known managed binary directories
if has brew; then
    BREW_PREFIX="$(brew --prefix)"
    for dir in "$BREW_PREFIX/bin" "$BREW_PREFIX/sbin"; do
        [[ -d "$dir" ]] && ls "$dir" 2>/dev/null >> "$MANAGED_BINS"
    done
fi
if has npm; then
    NPM_BIN="$(npm bin -g 2>/dev/null || echo "")"
    [[ -d "$NPM_BIN" ]] && ls "$NPM_BIN" 2>/dev/null >> "$MANAGED_BINS"
fi
if has pipx; then
    pipx list --short 2>/dev/null | awk '{print $1}' >> "$MANAGED_BINS"
fi
# uv-managed tool binaries
if has uv; then
    UV_BIN="$(uv tool dir 2>/dev/null)/bin" 2>/dev/null || true
    [[ -d "$UV_BIN" ]] && ls "$UV_BIN" 2>/dev/null >> "$MANAGED_BINS"
fi
# pnpm-managed global binaries
if has pnpm; then
    PNPM_BIN="$(pnpm bin -g 2>/dev/null || echo "")"
    [[ -d "$PNPM_BIN" ]] && ls "$PNPM_BIN" 2>/dev/null >> "$MANAGED_BINS"
fi
# yarn-managed global binaries
if has yarn; then
    YARN_BIN="$(yarn global bin 2>/dev/null || echo "")"
    [[ -d "$YARN_BIN" ]] && ls "$YARN_BIN" 2>/dev/null >> "$MANAGED_BINS"
fi
# deno-managed binaries
[[ -d "$HOME/.deno/bin" ]] && ls "$HOME/.deno/bin" 2>/dev/null >> "$MANAGED_BINS"
# bun-managed global binaries
if has bun; then
    BUN_BIN="$(bun pm bin -g 2>/dev/null || echo "")"
    [[ -d "$BUN_BIN" ]] && ls "$BUN_BIN" 2>/dev/null >> "$MANAGED_BINS"
fi
# mise-managed binaries (shims)
[[ -d "$HOME/.local/share/mise/shims" ]] && ls "$HOME/.local/share/mise/shims" 2>/dev/null >> "$MANAGED_BINS"
for dir in "$HOME/.cargo/bin" "${GOBIN:-${GOPATH:-$HOME/go}/bin}"; do
    [[ -d "$dir" ]] && ls "$dir" 2>/dev/null >> "$MANAGED_BINS"
done
if has gem; then
    GEM_BIN="$(gem environment gemdir 2>/dev/null)/bin"
    [[ -d "$GEM_BIN" ]] && ls "$GEM_BIN" 2>/dev/null >> "$MANAGED_BINS"
fi
if has composer; then
    COMPOSER_BIN="$(composer global config bin-dir --absolute 2>/dev/null || echo "")"
    [[ -d "$COMPOSER_BIN" ]] && ls "$COMPOSER_BIN" 2>/dev/null >> "$MANAGED_BINS"
fi

# System binaries to exclude (macOS defaults)
cat >> "$MANAGED_BINS" << 'SYSTEM'
bash
cat
cd
chmod
cp
curl
date
dd
df
diff
dirname
du
echo
env
expr
find
grep
head
hostname
id
kill
less
ln
ls
man
mkdir
more
mv
nano
open
passwd
pax
perl
php
ps
pwd
python3
readlink
rm
rmdir
ruby
say
scp
sed
sftp
sh
sleep
sort
ssh
su
sudo
sw_vers
sysctl
tail
tar
tee
test
top
touch
tr
uname
uniq
vi
vim
wc
which
who
xargs
zip
zsh
SYSTEM

SCAN_DIRS="/usr/local/bin /opt/homebrew/bin $HOME/.local/bin"
UNMANAGED="$(mktemp)"

for dir in $SCAN_DIRS; do
    [[ -d "$dir" ]] || continue
    for bin in "$dir"/*; do
        [[ -x "$bin" ]] || continue
        name="$(basename "$bin")"
        if ! grep -qxF "$name" "$MANAGED_BINS" 2>/dev/null; then
            echo "$name" >> "$UNMANAGED"
        fi
    done
done

UNMANAGED_LIST="$(sort -u "$UNMANAGED" 2>/dev/null || true)"
rm -f "$UNMANAGED"

if [[ -n "$UNMANAGED_LIST" ]]; then
    UNMANAGED_COUNT="$(echo "$UNMANAGED_LIST" | wc -l | tr -d ' ')"
    ok "Found $UNMANAGED_COUNT unmanaged CLIs"

    cat >> "$RESTORE" << 'EOF'
review_unmanaged_clis() {
    info "The following CLIs were found but not managed by any known package manager."
    info "Review these and install manually if needed:"
    echo ""
    local clis=(
EOF

    while IFS= read -r cli; do
        [[ -n "$cli" ]] && printf '        "%s"\n' "$cli" >> "$RESTORE"
    done <<< "$UNMANAGED_LIST"

    cat >> "$RESTORE" << 'EOF'
    )
    for c in "${clis[@]}"; do
        echo "  - $c"
    done
    echo ""
    warn "These may have been installed via direct download, curl|bash, or other means."
}

EOF
else
    ok "No unmanaged CLIs detected"
    emit_stub_section "review_unmanaged_clis" "No unmanaged CLIs were detected at snapshot time"
fi

# ---------------------------------------------------------------------------
# Unmanaged GUI apps (not from brew cask, App Store, or macOS built-in)
# ---------------------------------------------------------------------------

info "Scanning for unmanaged GUI apps..."

MANAGED_APPS="$(mktemp)"

# Brew-cask-managed apps
if has brew; then
    CASK_LIST="$(brew list --cask -1 2>/dev/null)"
    if [[ -n "$CASK_LIST" ]]; then
        brew info --json=v2 --cask $CASK_LIST 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for cask in data.get('casks', []):
    for a in cask.get('artifacts', []):
        if isinstance(a, dict) and 'app' in a:
            for app in a['app']:
                print(app.replace('.app', ''))
" >> "$MANAGED_APPS" 2>/dev/null
    fi
fi

# Mac App Store apps
if has mas; then
    mas list 2>/dev/null | sed 's/^[[:space:]]*[0-9]*//' | sed 's/[[:space:]]*([^)]*)[[:space:]]*$//' | sed 's/^[[:space:]]*//' >> "$MANAGED_APPS"
fi

# macOS built-in apps
cat >> "$MANAGED_APPS" << 'BUILTIN'
App Store
Automator
Books
Calculator
Calendar
Chess
Clock
Contacts
Dictionary
FaceTime
Freeform
Home
Image Capture
Launchpad
Mail
Maps
Messages
Migration Assistant
Music
News
Notes
Photo Booth
Photos
Podcasts
Preview
QuickTime Player
Reminders
Safari
Shortcuts
Siri
Stickies
Stocks
System Preferences
System Settings
TV
TextEdit
Time Machine
Tips
Utilities
Voice Memos
Weather
BUILTIN

ALL_APPS="$(ls /Applications/ 2>/dev/null | grep '\.app$' | sed 's/\.app$//' | sort)"
UNMANAGED_APPS="$(comm -23 <(echo "$ALL_APPS") <(sort -u "$MANAGED_APPS") 2>/dev/null || true)"
rm -f "$MANAGED_APPS"

if [[ -n "$UNMANAGED_APPS" ]]; then
    UNMANAGED_APP_COUNT="$(echo "$UNMANAGED_APPS" | wc -l | tr -d ' ')"
    ok "Found $UNMANAGED_APP_COUNT unmanaged GUI apps"

    cat >> "$RESTORE" << 'EOF'
review_unmanaged_apps() {
    info "The following GUI apps were found but not managed by Homebrew or the App Store."
    info "These were likely installed via .dmg download. Review and reinstall manually if needed:"
    echo ""
    local apps=(
EOF

    while IFS= read -r app; do
        [[ -n "$app" ]] && printf '        "%s"\n' "$app" >> "$RESTORE"
    done <<< "$UNMANAGED_APPS"

    cat >> "$RESTORE" << 'EOF'
    )
    for a in "${apps[@]}"; do
        echo "  - $a"
    done
    echo ""
    warn "Check if any of these are available as Homebrew casks: brew search <name>"
}

EOF
else
    ok "No unmanaged GUI apps detected"
    emit_stub_section "review_unmanaged_apps" "No unmanaged GUI apps were detected at snapshot time"
fi

# ---------------------------------------------------------------------------
# Main execution block
# ---------------------------------------------------------------------------

cat >> "$RESTORE" << 'MAIN'
# =========================================================================
# Main
# =========================================================================

main() {
    echo ""
    info "=== SnapMac Restore ==="
    echo ""

    ensure_xcode_clt
    echo ""
    install_homebrew
    echo ""
    install_from_brewfile
    echo ""
    review_sketch_plugins
    echo ""
    install_cursor_extensions
    echo ""
    install_npm_globals
    echo ""
    install_pip3_packages
    echo ""
    install_pipx_packages
    echo ""
    install_uv_tools
    echo ""
    install_pnpm_globals
    echo ""
    install_yarn_globals
    echo ""
    install_deno_packages
    echo ""
    install_bun_globals
    echo ""
    install_mise_tools
    echo ""
    install_cargo_packages
    echo ""
    install_ruby_gems
    echo ""
    install_go_binaries
    echo ""
    install_composer_packages
    echo ""
    review_unmanaged_clis
    echo ""
    review_unmanaged_apps

    echo ""
    if [[ $FAILURES -gt 0 ]]; then
        warn "Restore completed with $FAILURES failure(s). Review output above."
    else
        ok "Restore completed successfully!"
    fi
}

main "$@"
MAIN

chmod +x "$RESTORE"

echo ""
ok "Snapshot complete!"
ok "Restore script: $RESTORE"
ok "Run it on a new machine with: bash $RESTORE"

if [[ "$PUSH" == true ]]; then
    echo ""
    bash "$SCRIPT_DIR/push-snapshot.sh" "$SNAPSHOT_DIR"
fi
