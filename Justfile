# Justfile for MyEmacs (Vanilla Emacs Configuration)

default:
    @just --list

# ── Development ──────────────────────────────────────────────────────

# Launch Emacs with this config
run:
    emacs --init-directory "$(pwd)"

# Install/refresh packages (non-interactive)
install:
    emacs --init-directory "$(pwd)" --batch -l init.el --eval '(message "Packages installed.")'

# ── Quality Checks (Lint + Compile) ─────────────────────────────────

# Byte-compile lisp directory (catches: undefined functions, obsolete vars, syntax errors)
compile:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(setq byte-compile-error-on-warn t)' \
      --eval '(byte-recompile-directory (expand-file-name "lisp" user-emacs-directory) 0)'

# Checkdoc: validates docstring conventions (Emacs Lisp standards)
checkdoc:
    emacs --batch -Q \
      --eval '(setq checkdoc-verbose t)' \
      --eval '(let ((errors 0)) (dolist (f (directory-files "lisp" t "\\.el$")) (condition-case nil (checkdoc-file f) (error (setq errors (1+ errors))))) (if (> errors 0) (error "checkdoc: %d files with issues" errors) (message "checkdoc: OK")))'

# Quick config load test (no linting)
check:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(message "Config loaded OK.")' && echo "✅ OK" || echo "❌ FAIL"

# Full lint suite: compile + checkdoc
lint: compile checkdoc
    @echo "✅ All lint checks passed"

# Enhanced check: loads + full lint (CI-friendly)
check-all: check lint
    @echo "✅✅ Full check passed"

# ── Sync & Deploy ────────────────────────────────────────────────────

# Sync to test directory (~/.config/emacs-vanilla)
sync:
    @echo "📦 Syncing to ~/.config/emacs-vanilla..."
    @cd ~/.config/emacs-vanilla && git stash && git pull && git stash pop && rm -f lisp/*.elc && echo "✅ Sync complete" || echo "❌ Sync failed"

# Test in sync directory
test:
    emacs --init-directory ~/.config/emacs-vanilla

# Full workflow: lint -> commit -> push -> sync -> test
deploy MSG:
    @echo "🚀 Deploying: {{MSG}}"
    just check-all && git add -A && git commit -m "{{MSG}}" && git push && just sync && just test

# CI target: runs everything needed for CI pipeline
ci: check-all
    @echo "✅ CI pipeline passed"
