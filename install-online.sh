#!/bin/sh
# =============================================================
# AmneziaWG online installer for Asuswrt-Merlin
# Usage: curl -sfL https://raw.githubusercontent.com/r0otx/asuswrt-merlin-amneziawg/main/install-online.sh | sh
# =============================================================

REPO="r0otx/asuswrt-merlin-amneziawg"
TMP_DIR="/tmp/amneziawg_install"

echo ""
echo "============================================"
echo "  AmneziaWG Installer"
echo "============================================"
echo ""

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    aarch64) PKG_ARCH="aarch64-3.10" ;;
    armv7l)  PKG_ARCH="armv7-2.6" ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        echo "Supported: aarch64, armv7l"
        exit 1
        ;;
esac
echo "Architecture: $ARCH ($PKG_ARCH)"

# Check Entware
if ! command -v opkg >/dev/null 2>&1; then
    echo "ERROR: Entware not installed. Install it first via amtm."
    exit 1
fi
echo "Entware: OK"

# Get latest release URL
echo "Fetching latest release..."
RELEASE_JSON=$(curl -sfL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null)
if [ -z "$RELEASE_JSON" ]; then
    echo "ERROR: Cannot reach GitHub API"
    exit 1
fi

VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//' | sed 's/".*//')
echo "Latest version: $VERSION"

# Find matching .ipk asset
IPK_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep "$PKG_ARCH" | grep '.ipk"' | head -1 | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"//' | sed 's/".*//')
if [ -z "$IPK_URL" ]; then
    echo "ERROR: No .ipk found for $PKG_ARCH in release $VERSION"
    exit 1
fi

IPK_FILE=$(basename "$IPK_URL")
echo "Package: $IPK_FILE"

# Download
mkdir -p "$TMP_DIR"
echo "Downloading..."
if ! curl -sfL "$IPK_URL" -o "$TMP_DIR/$IPK_FILE"; then
    echo "ERROR: Download failed"
    rm -rf "$TMP_DIR"
    exit 1
fi
echo "Downloaded: $TMP_DIR/$IPK_FILE"

# Install
echo "Installing..."
opkg install "$TMP_DIR/$IPK_FILE"
RC=$?

# Cleanup
rm -rf "$TMP_DIR"

if [ $RC -eq 0 ]; then
    echo ""
    echo "============================================"
    echo "  AmneziaWG $VERSION installed!"
    echo "============================================"
    echo "  Web UI:  VPN > AmneziaWG"
    echo "  Start:   /opt/etc/init.d/S99amneziawg start"
    echo ""
else
    echo "ERROR: Installation failed (exit code $RC)"
    exit 1
fi
