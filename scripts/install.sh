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
SCRIPT_NAME="miaoyan"

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
info "Downloading miaoyan CLI..."
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/scripts/miaoyan" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

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
info "MiaoYan CLI installed successfully! 🎉"
echo ""
echo "  Usage:"
echo "    miaoyan list              # List all notes"
echo "    miaoyan search <query>    # Search notes"
echo "    miaoyan open <title>      # Open note in MiaoYan"
echo "    miaoyan new <title>       # Create new note"
echo "    miaoyan cat <title>       # Print note content"
echo ""
echo "  Run 'miaoyan help' for more commands."
echo ""
