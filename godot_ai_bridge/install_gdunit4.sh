#!/usr/bin/env bash
set -euo pipefail

GDUNIT4_VERSION="v6.1.1"
DOWNLOAD_URL="https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/${GDUNIT4_VERSION}.zip"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDONS_DIR="${SCRIPT_DIR}/addons"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [ -d "${ADDONS_DIR}/gdUnit4" ]; then
    echo "addons/gdUnit4/ already exists — remove it first to reinstall."
    exit 1
fi

echo "Downloading GdUnit4 ${GDUNIT4_VERSION}..."
curl -fSL -o "${TMP_DIR}/gdunit4.zip" "$DOWNLOAD_URL"

echo "Extracting..."
unzip -q "${TMP_DIR}/gdunit4.zip" -d "$TMP_DIR"

# The zip extracts to gdUnit4-<version>/ (without the leading 'v')
EXTRACTED="$(ls -d "${TMP_DIR}"/gdUnit4-*/)"
cp -r "${EXTRACTED}addons/gdUnit4" "${ADDONS_DIR}/gdUnit4"

echo "Installed addons/gdUnit4/ (${GDUNIT4_VERSION})."
echo "Open Godot and enable the plugin under Project > Project Settings > Plugins."
