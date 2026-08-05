#!/usr/bin/env bash
# cutoff-migration.sh — Automate final Doom -> Vanilla Emacs migration
# Usage: ./bin/cutoff-migration.sh

set -euo pipefail

EMACS_DIR="$HOME/.config/emacs"
DOOM_DIR="$HOME/.config/doom"
MYEMACS_REPO="$HOME/Projects/Github/MyEmacs"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

echo "🚀 Starting Cutoff Migration (Doom Emacs -> MyEmacs Vanilla)..."

# 1. Back up existing configs
if [ -d "$EMACS_DIR" ] && [ ! -L "$EMACS_DIR" ]; then
    echo "📦 Backing up existing ~/.config/emacs directory..."
    mv "$EMACS_DIR" "${EMACS_DIR}.bak_${BACKUP_DATE}"
elif [ -L "$EMACS_DIR" ]; then
    echo "🔗 Removing existing ~/.config/emacs symlink..."
    rm "$EMACS_DIR"
fi

if [ -d "$DOOM_DIR" ]; then
    echo "📦 Backing up existing ~/.config/doom directory..."
    mv "$DOOM_DIR" "${DOOM_DIR}.bak_${BACKUP_DATE}"
fi

# 2. Create the symlink
echo "🔗 Creating symlink: $MYEMACS_REPO -> $EMACS_DIR"
ln -s "$MYEMACS_REPO" "$EMACS_DIR"

# 3. Clean up old bytecompiles
echo "🧹 Cleaning up any old compiled .elc files..."
find "$EMACS_DIR" -name "*.elc" -type f -delete

# 4. Verify startup in new configuration path
echo "🧪 Running configuration validation check..."
emacs --init-directory "$EMACS_DIR" --batch -l "$EMACS_DIR/init.el" --eval '(message "✅ Configuration validated successfully in ~/.config/emacs!")'

echo "🎉 Migration complete! You can now launch Emacs normally."
