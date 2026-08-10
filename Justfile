# Justfile for MyEmacs (Vanilla Emacs Configuration)

# ── Default ──────────────────────────────────────────────────────────

# List available recipes
default:
    @just --list

# ── Variables ────────────────────────────────────────────────────────

# Authoritative test/deploy environment (full elpaca builds; the repo may have
# stale gptel autoloads). Override with EMACS_TEST_DIR, e.g.:
#   just test EMACS_TEST_DIR="$(pwd)"
prod_dir := `echo "${EMACS_TEST_DIR:-$HOME/.config/emacs}"`

# ── Launch / Install ─────────────────────────────────────────────────

# Launch Emacs with this config (dev, repo directory)
run:
    emacs --init-directory "$(pwd)"

# Launch Emacs in production ({{prod_dir}})
test-run:
    emacs --init-directory "{{prod_dir}}"

# Install/refresh packages (non-interactive)
install:
    emacs --init-directory "$(pwd)" --batch -l init.el --eval '(message "Packages installed.")'

# ── Checks (boot + lint) ─────────────────────────────────────────────

# Quick config load test (dev, no linting)
check:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(message "Config loaded OK.")' && echo "✅ OK" || echo "❌ FAIL"

# Quick config load test (production, post-sync verification)
check-prod:
    emacs --init-directory "{{prod_dir}}" --batch -l init.el \
      --eval '(message "Config loaded OK.")' && echo "✅ OK" || echo "❌ FAIL"

# Byte-compile lisp directory, treating warnings as errors
compile:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(setq byte-compile-error-on-warn t)' \
      --eval '(byte-recompile-directory (expand-file-name "lisp" user-emacs-directory) 0)'

# Build native C/C++ modules (vterm-module, tree-sitter grammars)
compile-modules:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(setq vterm-always-compile-module t)' \
      --eval '(require '\''vterm nil t)' \
      --eval '(when (require '\''treesit-auto nil t) (let ((treesit-auto-install t)) (ignore-errors (treesit-auto-install-all))))'

# Checkdoc: validates docstring conventions (Emacs Lisp standards)
checkdoc:
    emacs --batch -Q \
      --eval '(setq checkdoc-verbose t)' \
      --eval '(let ((errors 0)) (dolist (f (directory-files "lisp" t "\\.el$")) (condition-case nil (checkdoc-file f) (error (setq errors (1+ errors))))) (if (> errors 0) (error "checkdoc: %d files with issues" errors) (message "checkdoc: OK")))'

# Lint: byte-compile + checkdoc
lint: compile checkdoc
    @echo "✅ Lint passed"

# ── Tests (ERT suite) ────────────────────────────────────────────────

# Run full ERT suite in batch (exit non-zero on failure)
test:
    emacs --init-directory "{{prod_dir}}" --batch -l init.el \
      -l tests/load-tests.el \
      --eval '(ert-run-tests-batch-and-exit t)'

# Alias of `test` (kept for compatibility with documented commands)
test-batch: test

# AI-only tests (offline asserts; network skipped without EMACS_TEST_NETWORK)
test-ai:
    emacs --init-directory "{{prod_dir}}" --batch -l init.el \
      -l tests/load-tests.el \
      --eval '(ert-run-tests-batch-and-exit "myemacs-ai")'

# Live network tests: real requests to every gptel backend (opt-in)
test-network:
    EMACS_TEST_NETWORK=1 just test

# Tests + lint (CI-friendly)
test-all: lint test
    @echo "✅✅ All tests passed"

# Run tests and generate local AI triage summary if there are errors
triage:
    @just check-all 2>&1 | python3 bin/log-triage

# ── Sync / Deploy / CI ───────────────────────────────────────────────

# Sync to production ({{prod_dir}}) via git: fetch + hard reset to origin/main
sync:
    @echo "📦 Syncing {{prod_dir}} to origin/main..."
    @test -d "{{prod_dir}}/.git" || { echo "❌ {{prod_dir}} is not a git clone. Run: git clone git@github.com:carlosalbertofilho/MyEmacs.git {{prod_dir}}"; exit 1; }
    @git -C "{{prod_dir}}" fetch origin
    @git -C "{{prod_dir}}" reset --hard origin/main
    @echo "✅ Sync complete (prod at $(git -C "{{prod_dir}}" rev-parse --short HEAD))"

# Full battery: boot check (dev) + lint + ERT suite
check-all: check test-all
    @echo "✅✅ Full check passed"

# Full workflow: check-all -> commit -> push -> sync -> verify prod boot
deploy MSG:
    @echo "🚀 Deploying: {{MSG}}"
    just check-all && git add -A && git commit -m "{{MSG}}" && git push && just sync && just check-prod

# CI target: runs everything needed for CI pipeline
ci: check-all
    @echo "✅ CI pipeline passed"

# Execute full Doom -> Vanilla migration (backup, copy repo to ~/.config/emacs, clean caches)
promote:
    python3 bin/promote-migration.py
