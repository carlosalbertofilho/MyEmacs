# Justfile for MyEmacs (Vanilla Emacs Configuration)

default:
    @just --list

# Launch Emacs with this config
run:
    emacs --init-directory "$(pwd)"

# Install/refresh packages (non-interactive)
install:
    emacs --init-directory "$(pwd)" --batch -l init.el --eval '(message "Packages installed.")'

# Byte-compile lisp directory
compile:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(byte-recompile-directory (expand-file-name "lisp" user-emacs-directory) 0)'

# Check config loads without errors
check:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(message "Config loaded OK.")' && echo "✅ OK" || echo "❌ FAIL"

# Sync to test directory (~/.config/emacs-vanilla)
# Usage: just sync
sync:
    @echo "📦 Syncing to ~/.config/emacs-vanilla..."
    @cd ~/.config/emacs-vanilla && git stash && git pull && git stash pop && echo "✅ Sync complete" || echo "❌ Sync failed"

# Test in sync directory
# Usage: just test
test:
    emacs --init-directory ~/.config/emacs-vanilla

# Full workflow: commit, push, sync, test
# Usage: just deploy "commit message"
deploy MSG:
    @echo "🚀 Deploying: {{MSG}}"
    git add -A && git commit -m "{{MSG}}" && git push && just sync && just test
