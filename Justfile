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

# ── Clean / Rebuild (build artifact hygiene) ─────────────────────────

# Remove stale byte-compiled objects (.elc/.eln) and native-comp cache
# (eln-cache/) in the repo. Verified: fails if any artifact survives.
clean:
    @target="$(pwd)"; \
    test -d "$target/lisp" || { echo "❌ $target/lisp not found; aborting clean."; exit 1; }; \
    rm -f "$target"/lisp/*.elc "$target"/lisp/*.eln; \
    rm -rf "$target"/eln-cache; \
    leftovers="$(ls "$target"/lisp/*.elc "$target"/lisp/*.eln 2>/dev/null)"; \
    test -z "$leftovers" || { echo "❌ Stale artifacts remain after clean:"; echo "$leftovers"; exit 1; }; \
    test ! -d "$target/eln-cache" || { echo "❌ eln-cache/ still present after clean"; exit 1; }; \
    echo "✅ Cleaned repo build artifacts (.elc + .eln + eln-cache)"

# Remove stale byte-compiled objects (.elc/.eln) and native-comp cache
# (eln-cache/) in {{prod_dir}}. Verified: fails if any artifact survives.
clean-prod:
    @target="{{prod_dir}}"; target="${target%/}"; \
    test -d "$target/lisp" || { echo "❌ $target/lisp not found; aborting clean-prod."; exit 1; }; \
    rm -f "$target"/lisp/*.elc "$target"/lisp/*.eln; \
    rm -rf "$target"/eln-cache; \
    leftovers="$(ls "$target"/lisp/*.elc "$target"/lisp/*.eln 2>/dev/null)"; \
    test -z "$leftovers" || { echo "❌ Stale artifacts remain after clean:"; echo "$leftovers"; exit 1; }; \
    test ! -d "$target/eln-cache" || { echo "❌ eln-cache/ still present after clean"; exit 1; }; \
    echo "✅ Cleaned prod build artifacts (.elc + .eln + eln-cache)"

# Rebuild byte-compiled objects from source in the repo (clean + compile)
rebuild: clean compile
    @echo "✅ Rebuilt (repo)"

# Rebuild byte-compiled objects from source in {{prod_dir}} (clean-prod + compile-prod)
rebuild-prod: clean-prod compile-prod
    @echo "✅ Rebuilt (prod)"

# ── Checks (boot + lint) ─────────────────────────────────────────────

# Quick config load test (dev, no linting)
check:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(message "Config loaded OK.")' && echo "✅ OK" || echo "❌ FAIL"

# Quick config load test (production, post-sync verification)
check-prod:
    emacs --init-directory "{{prod_dir}}" --batch -l init.el \
      --eval '(message "Config loaded OK.")' && echo "✅ OK" || echo "❌ FAIL"

# Byte-compile lisp directory in {{prod_dir}} (zero-warning gate, filtered output)
# Guaranteed: real emacs exit code is propagated (not masked by the filter pipe).
compile-prod:
    @output="$(emacs --init-directory "{{prod_dir}}" --batch -l init.el \
      --eval '(setq byte-compile-error-on-warn t)' \
      --eval '(byte-recompile-directory (expand-file-name "lisp" user-emacs-directory) 0)' 2>&1)"; \
    status=$?; \
    echo "$output" | rg -i 'error|warning|failed|done' \
      | rg -v 'Optimization failure|Unknown type: plist|epa-file|Unknown type jupyter|Unknown type magent-request-context' || true; \
    exit "$status"

# Nota: o repo pode ter builds elpaca parciais (ex.: falta tempel); o gate
# autoritativo pós-sync é o `compile-prod`.
# Byte-compile lisp directory in the repo (zero-warning gate, filtered output)
# Guaranteed: real emacs exit code is propagated (not masked by the filter pipe).
compile: compile-modules
    @output="$(emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(setq byte-compile-error-on-warn t)' \
      --eval '(byte-recompile-directory (expand-file-name "lisp" user-emacs-directory) 0)' 2>&1)"; \
    status=$?; \
    echo "$output" | rg -i 'error|warning|failed|done' \
      | rg -v 'Optimization failure|Unknown type: plist|epa-file|Unknown type jupyter|Unknown type magent-request-context' || true; \
    exit "$status"

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

# Lint org structure (balanced blocks, malformed headings, TODO.org naming)
org-lint:
    @emacs --batch -Q -l bin/org-lint.el --eval '(org-lint-run-and-exit)' 2>&1 || exit 1

# Lint: byte-compile + checkdoc + org structure
lint: compile checkdoc org-lint
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

# Full workflow: check-all -> commit -> push -> sync -> compile + boot check no prod
deploy MSG:
    @echo "🚀 Deploying: {{MSG}}"
    just check-all && git add -A && git commit -m "{{MSG}}" && git push && just sync && just compile-prod && just check-prod

# CI target: runs everything needed for CI pipeline
ci: check-all
    @echo "✅ CI pipeline passed"

# Execute full Doom -> Vanilla migration (backup, copy repo to ~/.config/emacs, clean caches)
promote:
    python3 bin/promote-migration.py
