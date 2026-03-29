# modules/data-science.sh — Data science tool capture.
#
# Covers: R packages, Jupyter kernels
# Requires: $RESTORE, $PIN_VERSIONS, info(), warn(), ok(), emit_stub_section()

snapshot_data_science() {
    # ---------------------------------------------------------------------------
    # R packages (special: batch install via Rscript; version pinning via remotes)
    # ---------------------------------------------------------------------------

    info "Scanning R packages..."
    if has Rscript; then
        local R_PKGS
        R_PKGS="$(Rscript --no-save --no-restore -e '
ip <- installed.packages()
user_pkgs <- ip[is.na(ip[,"Priority"]), c("Package","Version")]
cat(paste(user_pkgs[,"Package"], user_pkgs[,"Version"], sep=" ", collapse="\n"), "\n")
' 2>/dev/null | sed '/^$/d' || true)"

        if [[ -n "$R_PKGS" ]]; then
            local R_COUNT
            R_COUNT="$(echo "$R_PKGS" | wc -l | tr -d ' ')"
            ok "Found $R_COUNT R packages"

            cat >> "$RESTORE" << 'R_FUNC'
install_r_packages() {
    if ! has Rscript; then
        warn "Rscript not found — skipping R packages"
        warn "Install R: brew install --cask r"
        return
    fi
    info "Installing R packages..."
    local packages=(
R_FUNC

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
            done <<< "$R_PKGS"

            if [[ "$PIN_VERSIONS" == true ]]; then
                cat >> "$RESTORE" << 'R_FUNC'
    )
    local total=${#packages[@]}
    local i=0
    Rscript --no-save --no-restore -e "if (!requireNamespace('remotes', quietly=TRUE)) install.packages('remotes', repos='https://cloud.r-project.org')" 2>&1
    for p in "${packages[@]}"; do
        ((i++)) || true
        local pkg_name="${p%% *}"
        local pkg_ver="${p##* }"
        info "  [$i/$total] $pkg_name@$pkg_ver"
        install_or_warn Rscript --no-save --no-restore -e "remotes::install_version('$pkg_name', version='$pkg_ver', repos='https://cloud.r-project.org')"
    done
    ok "R packages done ($total packages)"
}

R_FUNC
            else
                cat >> "$RESTORE" << 'R_FUNC'
    )
    local total=${#packages[@]}
    local pkgs_r=""
    for p in "${packages[@]}"; do
        pkgs_r+="\"$p\","
    done
    pkgs_r="${pkgs_r%,}"
    info "Installing $total R packages from CRAN..."
    if Rscript --no-save --no-restore -e "install.packages(c($pkgs_r), repos='https://cloud.r-project.org')" 2>&1; then
        ok "R packages done ($total packages)"
    else
        err "Some R packages failed to install"
        ((FAILURES++)) || true
    fi
}

R_FUNC
            fi
        else
            ok "No user-installed R packages found"
            emit_stub_section "install_r_packages" "No R packages were captured in this snapshot"
        fi
    else
        info "Rscript not found — skipping R packages"
        emit_stub_section "install_r_packages" "No R packages were captured (R was not installed at snapshot time)"
    fi

    # ---------------------------------------------------------------------------
    # Jupyter kernels
    # ---------------------------------------------------------------------------

    info "Scanning Jupyter kernels..."
    if has jupyter; then
        local JUPYTER_KERNELS
        JUPYTER_KERNELS="$(jupyter kernelspec list 2>/dev/null \
            | tail -n +2 \
            | awk '{print $1}' \
            | grep -v '^python3$' || true)"

        if [[ -n "$JUPYTER_KERNELS" ]]; then
            local JUPYTER_COUNT
            JUPYTER_COUNT="$(echo "$JUPYTER_KERNELS" | wc -l | tr -d ' ')"
            ok "Found $JUPYTER_COUNT additional Jupyter kernels"

            cat >> "$RESTORE" << 'EOF'
review_jupyter_kernels() {
    info "The following Jupyter kernels were installed at snapshot time (excluding default python3)."
    info "Reinstall via the appropriate package manager for each kernel:"
    echo ""
    local kernels=(
EOF
            while IFS= read -r kernel; do
                [[ -n "$kernel" ]] && printf '        "%s"\n' "$kernel" >> "$RESTORE"
            done <<< "$JUPYTER_KERNELS"
            cat >> "$RESTORE" << 'EOF'
    )
    for k in "${kernels[@]}"; do
        echo "  - $k"
    done
    echo ""
    info "Examples: pip install ipykernel (Python), install.packages('IRkernel') then IRkernel::installspec() (R)"
}

EOF
        else
            ok "No additional Jupyter kernels found"
            emit_stub_section "review_jupyter_kernels" "No additional Jupyter kernels were captured in this snapshot"
        fi
    else
        info "jupyter not found — skipping kernel scan"
        emit_stub_section "review_jupyter_kernels" "No Jupyter kernels were captured (jupyter was not installed at snapshot time)"
    fi

    RESTORE_MAIN_CALLS+=(install_r_packages review_jupyter_kernels)
}
