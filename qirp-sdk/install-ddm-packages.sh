#!/usr/bin/env bash

# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

# install-ddm-packages.sh
#
# Installs, at runtime, the packages that were excluded from a DDM image
# (see build-utils' --ddm build flag and packages/ddm/<flavor>.manifest).
# Run this on a DDM device to restore the packages that a formal build
# would normally ship.
#
# Usage:
#   ./install-ddm-packages.sh [manifest_path]
#
# manifest_path defaults to packages/ddm/server.manifest next to this
# script (i.e. /usr/share/qirp-sdk/packages/ddm/server.manifest once
# installed on-device).

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Preseed debconf answers for packages known to prompt interactively, so a
# non-interactive install never blocks waiting on input.
printf '%s\n' \
    'landscape-common landscape-common/sysinfo select Do not display sysinfo on login' \
    | debconf-set-selections

# Clear out any package left half-configured by a previous interrupted run
# before installing more, so dpkg doesn't refuse to proceed.
dpkg --configure -a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PATH="${1:-$SCRIPT_DIR/packages/ddm/server.manifest}"

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

if [ ! -f "$MANIFEST_PATH" ]; then
    log_error "DDM manifest not found: $MANIFEST_PATH"
    exit 1
fi

# Strip comments (#...) and blank lines, take just the package name
# (first whitespace-separated field, ignoring any version pin).
mapfile -t packages < <(grep -v '^\s*#' "$MANIFEST_PATH" | awk 'NF {print $1}')

if [ "${#packages[@]}" -eq 0 ]; then
    log_info "No packages listed in $MANIFEST_PATH. Nothing to install."
    exit 0
fi

log_info "Installing ${#packages[@]} DDM-excluded package(s) from $MANIFEST_PATH..."

# The sample packages below download their models into /opt/model from their
# postinst. In the DDM image that postinst ran at build time, before wget and
# sudo (both in the DDM exclude manifest) were available, so no model was
# fetched. Re-run the postinst now that those tools are installed. Their
# postinsts tolerate download failures, so this never fails the script.
MODEL_POSTINST_PACKAGES=(
    ros-jazzy-sample-hand-detection
    ros-jazzy-sample-face-detection
    ros-jazzy-sample-hrnet-pose-estimation
    ros-jazzy-sample-resnet101
    ros-jazzy-sample-depth-estimation
)

rerun_model_postinsts() {
    local package script
    for package in "${MODEL_POSTINST_PACKAGES[@]}"; do
        script="/var/lib/dpkg/info/${package}.postinst"
        if [ ! -x "$script" ]; then
            log_info "No postinst for $package, skipping model download"
            continue
        fi
        log_info "Re-running postinst to download models: $package"
        "$script" configure || log_error "postinst failed for $package (models may be missing in /opt/model)"
    done
}

apt-get update

# Fetch all .debs before unpack/configure starts; ignore failures here
# since the install attempt below re-fetches as needed and still falls back.
SECONDS=0
NEEDRESTART_MODE=l apt-get install --reinstall -y --download-only "${packages[@]}" || true
log_info "Download took ${SECONDS}s"

# One transaction resolves dependencies once instead of per package.
SECONDS=0
if NEEDRESTART_MODE=l apt-get install --reinstall -y "${packages[@]}"; then
    log_info "Install took ${SECONDS}s"
    rerun_model_postinsts
    log_info "All DDM-excluded packages installed successfully."
    exit 0
fi
log_info "Install took ${SECONDS}s (failed)"

# Fall back to installing one at a time to isolate which package(s) failed.
log_error "Batched install failed; retrying packages individually to isolate the failure(s)."

# DDM stubs are left with desired-action "purge" as a marker (dpkg -l shows
# "pi"); once the real package replaces one it flips to "install" ("ii").
# Skip only on that exact match -- anything else gets a real attempt.
is_real_package_installed() {
    [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
}

SECONDS=0
failed=()
for package in "${packages[@]}"; do
    if is_real_package_installed "$package"; then
        log_info "Already installed, skipping: $package"
        continue
    fi

    log_info "Installing package: $package"
    if NEEDRESTART_MODE=l apt-get install --reinstall -y "$package"; then
        log_info "Successfully installed: $package"
    else
        log_error "Failed to install: $package"
        failed+=("$package")
    fi
done
log_info "Fallback install took ${SECONDS}s"

# Run regardless of unrelated package failures below (e.g. one unavailable
# package must not skip the model downloads).
rerun_model_postinsts

if [ "${#failed[@]}" -ne 0 ]; then
    log_error "Failed to install ${#failed[@]} package(s): ${failed[*]}"
    exit 1
fi

log_info "All DDM-excluded packages installed successfully."
