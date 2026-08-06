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

# Build native C/C++ modules (vterm-module, tree-sitter grammars)
compile-modules:
	emacs --init-directory "$(pwd)" --batch -l init.el \
	  --eval '(setq vterm-always-compile-module t)' \
	  --eval '(require '\''vterm nil t)' \
	  --eval '(when (require '\''treesit-auto nil t) (let ((treesit-auto-install t)) (ignore-errors (treesit-auto-install-all))))'

# Byte-compile lisp directory and native modules
compile: compile-modules
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
check-all: check test-all
    @echo "✅✅ Full check passed"

# ── Tests (ERT suite) ────────────────────────────────────────────────

# Authoritative test environment (full elpaca builds; repo may have stale gptel)
EMACS_TEST_DIR := `echo "$HOME/.config/emacs-vanilla"`

# Run full ERT suite in batch (exit non-zero on failure)
test-batch:
    emacs --init-directory "{{EMACS_TEST_DIR}}" --batch -l init.el \
      -l tests/load-tests.el \
      --eval '(ert-run-tests-batch-and-exit t)'

# AI-only tests (offline asserts; network skipped without EMACS_TEST_NETWORK)
test-ai:
    emacs --init-directory "{{EMACS_TEST_DIR}}" --batch -l init.el \
      -l tests/load-tests.el \
      --eval '(ert-run-tests-batch-and-exit "myemacs-ai")'

# Live network tests: real requests to every gptel backend (opt-in)
test-network:
    EMACS_TEST_NETWORK=1 just test-batch

# Tests + lint (CI-friendly)
test-all: compile checkdoc test-batch
    @echo "✅✅ All tests passed"

# Run tests and generate local AI triage summary if there are errors
triage:
    @just check-all 2>&1 | python3 bin/log-triage

# ── Sync & Deploy ────────────────────────────────────────────────────

# Sync to test directory (~/.config/emacs-vanilla)
sync:
    @echo "📦 Syncing to ~/.config/emacs-vanilla..."
    @cd ~/.config/emacs-vanilla && (git diff --quiet || git stash) && git pull && (git stash pop 2>/dev/null || true) && find . -name "*.elc" -type f -delete && echo "✅ Sync complete"

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
