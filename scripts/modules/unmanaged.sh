# modules/unmanaged.sh — Detect CLIs and GUI apps not managed by any known package manager.
#
# Requires: $RESTORE, info(), warn(), ok(), emit_stub_section(), has()

snapshot_unmanaged() {
    # ---------------------------------------------------------------------------
    # Unmanaged CLIs
    # ---------------------------------------------------------------------------

    info "Scanning for unmanaged CLIs in PATH..."

    local MANAGED_BINS
    MANAGED_BINS="$(mktemp)"
    trap 'rm -f "$MANAGED_BINS"' EXIT

    # Collect all known managed binary directories
    if has brew; then
        local BREW_PREFIX
        BREW_PREFIX="$(brew --prefix)"
        local dir
        for dir in "$BREW_PREFIX/bin" "$BREW_PREFIX/sbin"; do
            [[ -d "$dir" ]] && ls "$dir" 2>/dev/null >> "$MANAGED_BINS"
        done
    fi
    if has npm; then
        local NPM_BIN
        NPM_BIN="$(npm bin -g 2>/dev/null || echo "")"
        [[ -d "$NPM_BIN" ]] && ls "$NPM_BIN" 2>/dev/null >> "$MANAGED_BINS"
    fi
    if has pipx; then
        pipx list --short 2>/dev/null | awk '{print $1}' >> "$MANAGED_BINS"
    fi
    if has uv; then
        local UV_BIN
        UV_BIN="$(uv tool dir 2>/dev/null)/bin" 2>/dev/null || true
        [[ -d "$UV_BIN" ]] && ls "$UV_BIN" 2>/dev/null >> "$MANAGED_BINS"
    fi
    if has pnpm; then
        local PNPM_BIN
        PNPM_BIN="$(pnpm bin -g 2>/dev/null || echo "")"
        [[ -d "$PNPM_BIN" ]] && ls "$PNPM_BIN" 2>/dev/null >> "$MANAGED_BINS"
    fi
    if has yarn; then
        local YARN_BIN
        YARN_BIN="$(yarn global bin 2>/dev/null || echo "")"
        [[ -d "$YARN_BIN" ]] && ls "$YARN_BIN" 2>/dev/null >> "$MANAGED_BINS"
    fi
    [[ -d "$HOME/.deno/bin" ]] && ls "$HOME/.deno/bin" 2>/dev/null >> "$MANAGED_BINS"
    if has bun; then
        local BUN_BIN
        BUN_BIN="$(bun pm bin -g 2>/dev/null || echo "")"
        [[ -d "$BUN_BIN" ]] && ls "$BUN_BIN" 2>/dev/null >> "$MANAGED_BINS"
    fi
    [[ -d "$HOME/.local/share/mise/shims" ]] && ls "$HOME/.local/share/mise/shims" 2>/dev/null >> "$MANAGED_BINS"
    for dir in "$HOME/.cargo/bin" "${GOBIN:-${GOPATH:-$HOME/go}/bin}"; do
        [[ -d "$dir" ]] && ls "$dir" 2>/dev/null >> "$MANAGED_BINS"
    done
    if has gem; then
        local GEM_BIN
        GEM_BIN="$(gem environment gemdir 2>/dev/null)/bin"
        [[ -d "$GEM_BIN" ]] && ls "$GEM_BIN" 2>/dev/null >> "$MANAGED_BINS"
    fi
    if has composer; then
        local COMPOSER_BIN
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

    local SCAN_DIRS="/usr/local/bin /opt/homebrew/bin $HOME/.local/bin"
    local UNMANAGED
    UNMANAGED="$(mktemp)"

    local bin name
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

    local UNMANAGED_LIST
    UNMANAGED_LIST="$(sort -u "$UNMANAGED" 2>/dev/null || true)"
    rm -f "$UNMANAGED"

    if [[ -n "$UNMANAGED_LIST" ]]; then
        local UNMANAGED_COUNT
        UNMANAGED_COUNT="$(echo "$UNMANAGED_LIST" | wc -l | tr -d ' ')"
        ok "Found $UNMANAGED_COUNT unmanaged CLIs"

        cat >> "$RESTORE" << 'EOF'
review_unmanaged_clis() {
    info "The following CLIs were found but not managed by any known package manager."
    info "Review these and install manually if needed:"
    echo ""
    local clis=(
EOF
        local cli
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
    # Unmanaged GUI apps
    # ---------------------------------------------------------------------------

    info "Scanning for unmanaged GUI apps..."

    local MANAGED_APPS
    MANAGED_APPS="$(mktemp)"

    if has brew; then
        local CASK_LIST
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

    if has mas; then
        mas list 2>/dev/null | sed 's/^[[:space:]]*[0-9]*//' | sed 's/[[:space:]]*([^)]*)[[:space:]]*$//' | sed 's/^[[:space:]]*//' >> "$MANAGED_APPS"
    fi

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

    local ALL_APPS UNMANAGED_APPS
    ALL_APPS="$(ls /Applications/ 2>/dev/null | grep '\.app$' | sed 's/\.app$//' | sort)"
    UNMANAGED_APPS="$(comm -23 <(echo "$ALL_APPS") <(sort -u "$MANAGED_APPS") 2>/dev/null || true)"
    rm -f "$MANAGED_APPS"

    if [[ -n "$UNMANAGED_APPS" ]]; then
        local UNMANAGED_APP_COUNT
        UNMANAGED_APP_COUNT="$(echo "$UNMANAGED_APPS" | wc -l | tr -d ' ')"
        ok "Found $UNMANAGED_APP_COUNT unmanaged GUI apps"

        cat >> "$RESTORE" << 'EOF'
review_unmanaged_apps() {
    info "The following GUI apps were found but not managed by Homebrew or the App Store."
    info "These were likely installed via .dmg download. Review and reinstall manually if needed:"
    echo ""
    local apps=(
EOF
        local app
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

    RESTORE_MAIN_CALLS+=(review_unmanaged_clis review_unmanaged_apps)
}
