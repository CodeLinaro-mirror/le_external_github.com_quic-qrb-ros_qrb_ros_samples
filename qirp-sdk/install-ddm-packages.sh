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

sudo DEBIAN_FRONTEND=noninteractive apt-get update

failed=()
for package in "${packages[@]}"; do
    log_info "Installing package: $package"
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"; then
        log_info "Successfully installed: $package"
    else
        log_error "Failed to install: $package"
        failed+=("$package")
    fi
done

if [ "${#failed[@]}" -ne 0 ]; then
    log_error "Failed to install ${#failed[@]} package(s): ${failed[*]}"
    exit 1
fi

log_info "All DDM-excluded packages installed successfully."
