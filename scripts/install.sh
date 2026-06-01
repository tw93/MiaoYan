#!/bin/bash
#
# MiaoYan CLI Installer
# https://github.com/tw93/MiaoYan
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tw93/MiaoYan/main/scripts/install.sh | bash
#

set -e

REPO="tw93/MiaoYan"
INSTALL_DIR="${MIAOYAN_INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_NAME="miao"
ALIAS_NAME="miaoyan"

# Source ref for the `miao` script. Defaults to the latest GitHub release tag
# so a bad push to main cannot break new installs. Set MIAOYAN_INSTALL_REF to
# override (e.g. `MIAOYAN_INSTALL_REF=main` for local development).
INSTALL_REF="${MIAOYAN_INSTALL_REF:-}"
if [[ -z "$INSTALL_REF" ]]; then
    INSTALL_REF=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -m1 '"tag_name"' \
        | cut -d'"' -f4)
    if [[ -z "$INSTALL_REF" ]]; then
        warn "Could not resolve latest release tag, falling back to main"
        INSTALL_REF="main"
    fi
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}▸${NC} $1"; }
warn() { echo -e "${YELLOW}▸${NC} $1"; }
error() { echo -e "${RED}▸${NC} $1" >&2; exit 1; }

# Check macOS
[[ "$(uname)" != "Darwin" ]] && error "MiaoYan CLI is macOS only."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download script
info "Downloading miao CLI (ref: $INSTALL_REF)..."
curl -fsSL "https://raw.githubusercontent.com/$REPO/$INSTALL_REF/scripts/miaoyan" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Create alias symlink
ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$ALIAS_NAME"

# Check PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    warn "$INSTALL_DIR is not in PATH"
    
    # Detect shell config
    SHELL_CONFIG=""
    if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
        SHELL_CONFIG="$HOME/.bash_profile"
    fi
    
    if [[ -n "$SHELL_CONFIG" ]]; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_CONFIG"
        info "Added $INSTALL_DIR to PATH in $SHELL_CONFIG"
        warn "Run 'source $SHELL_CONFIG' or restart terminal"
    else
        warn "Add this to your shell config:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi
fi

echo ""
info "Miao CLI installed successfully! 🎉"
echo ""
echo "  Usage:"
echo "    miao open <title|path>    # Open note"
echo "    miao new <title> [text]   # Create new note"
echo "    miao search <query>       # Search notes in terminal"
echo "    miao list [folder]        # List top-level folders, or markdown in folder"
echo "    miao cat <title|path>     # Print note content"
echo ""
echo "  Run 'miao help' for more commands."
echo ""
