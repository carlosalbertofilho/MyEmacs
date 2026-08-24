---
name: myemacs-native-tools
description: "Strict guidelines on using MyEmacs native smart-edit tools instead of default file modification tools."
---

# MyEmacs Native Tools (Soberania de Edição)

## The Golden Rule (Regra de Ouro)

When working within the `MyEmacs` repository (`/Users/carlosfilho/Projects/Github/MyEmacs`), you **MUST ABSOLUTELY PREFER** using the native Emacs AST-aware tools to edit files rather than relying on your default capabilities (`write_to_file`, `replace_file_content`, multi-edit patches, or arbitrary bash `sed`/`echo`).

Applies to: `.el`, `.org`, `.sh`/`.bash`, `.py`, `.ts`/`.js`, `.c`/`.h`, `.go`, `.md`, `.nix`, `.rs`.

## Why?

Default tools manipulate raw text: they break ASTs, miscount parentheses in bulk edits, and bypass validation. Real incident (2026-08-24): a hand-written structural patch with a wrong anchor + hand-counted closers corrupted `custom-magent-tool-smart-edit.el` repeatedly. The native tools exist precisely to make that error class impossible: they are **transactional** (snapshot → mutation → gate → save; byte-for-byte restore on failure).

## Transactional guarantee (all smart-edit mutations)

1. Snapshot of the whole buffer before any change.
2. Mutation runs inside a thunk.
3. Gate before saving: `org-lint` for `.org`; `check-parens` (+ language checks) for code.
4. On gate failure: buffer restored byte-a-byte from snapshot, restore persisted, error returned as message (never a half-edited file).

## How to invoke

From the repository root:

```bash
# Repo context (fast, no package bootstrap):
emacs --batch -Q -L lisp -l custom-magent-tool-smart-edit \
  --eval '(message (+carlos/magent-tool-org-smart-edit "FILE" "ACTION" ...))'

# Full environment (when other custom-* deps are needed):
emacs --batch -l init.el --eval '(message (+carlos/magent-tool-context_search "query"))'
```

Prefer writing complex call scripts to a temp `.el` under `/tmp` and running `emacs --batch -Q -l script.el` — avoids shell-quoting corruption of nested quotes. One-liners are fine for simple calls.

---

## 1. Smart-Edit Family (transactional file editing)

One tool per language, same signature:
`(plus-carlos TOOL TARGET-FILE ACTION &optional SNIPPET-NAME ARGS REASON)`

| Tool | File types | Extra validations |
|------|-----------|-------------------|
| `+carlos/magent-tool-elisp-smart-edit` | `.el` | check-parens |
| `+carlos/magent-tool-nix-smart-edit` | `.nix` | delimiters |
| `+carlos/magent-tool-python-smart-edit` | `.py` | py-compile/ruff |
| `+carlos/magent-tool-ts-smart-edit` | `.ts`/`.js` | prettier/eslint |
| `+carlos/magent-tool-c-smart-edit` | `.c`/`.h` | Norminette 42 |
| `+carlos/magent-tool-go-smart-edit` | `.go` | gofmt/gopls |
| `+carlos/magent-tool-org-smart-edit` | `.org` | **org-lint gate** |
| `+carlos/magent-tool-sh-smart-edit` | `.sh`/`.bash` | shellcheck |
| `+carlos/magent-tool-markdown-smart-edit` | `.md` | markdownlint |
| `+carlos/magent-tool-rust-smart-edit` | `.rs` | rustfmt/cargo |

Shared actions: `insert_snippet`, `refactor_symbol`, `validate_buffer`.

### Org actions (canonical reference)

```elisp
;; Rename EXACTLY one heading (matched by exact :raw-value via AST);
;; preserves level, TODO keyword, priority cookie and tags:
(org-smart-edit "TODO.org" "replace_heading" nil
                "Tarefa Alpha|Tarefa Alpha Renomeada")

;; Global replace with optional FLAGS (3rd token of ARGS):
;;   ALL (default) | FIRST | WORD (symbol boundaries) | REGEX
(org-smart-edit "TODO.org" "refactor_symbol" nil "old new FIRST")
(org-smart-edit "TODO.org" "refactor_symbol" nil "old new WORD")

;; Line-range-restricted replace; errors on invalid range:
(org-smart-edit "TODO.org" "replace_text" nil "old|new|L1|L2")

;; Property on the AST-anchored node (exact raw-value match):
(org-smart-edit "TODO.org" "set_property" nil "Heading Exato|STATUS|DONE")
```

Snippets (SNIPPET-NAME): `heading`, `properties_drawer`, `table`, `src_block`.

### Elisp snippets

`defun`, `deftest`, `defcustom`, `use-package`, `with-eval-after-load`.
Elisp-only action: `extract_sexp` (moves a sexp to another file, validating both).

---

## 2. Context & Knowledge (RAG)

```bash
# Semantic search over project .org/.el knowledge:
(+carlos/magent-tool-context_search "QUERY" &optional DIRECTORY)

# Generate/update reference docs under docs/ from live Elisp introspection
# (zero network, canonical header, :RAG:DOCS: tags):
(+carlos/magent-tool-rag-create-doc SYMBOLS TARGET-FILE TITLE DESCRIPTION
                                    &optional FILETAGS REASON)
```

## 3. Code Intelligence

```bash
(+carlos/magent-tool-flycheck-errors PATH)                 # diagnostics for a file
(+carlos/magent-tool-lsp-navigation "SYM" &optional ACTION) # definition/references
(+carlos/magent-tool-lsp ACTION PATH QUERY-STR)             # generic lsp-bridge
(+carlos/magent-tool-treesit-query LANG "QUERY" &rest ARGS) # tree-sitter AST query
(+carlos/magent-tool-snippet-expand NAME &optional ACTION MODE) # tempel expansion
```

## 4. Git / Forge (`custom-magent-tool-git.el`)

```bash
magit-status / magit-stage / magit-commit / magit-push / magit-pull
magit-checkout / magit-diff / magit-log / magit-merge / magit-rebase
magit-branch-list / magit-branch-delete
magit-submodule-list / magit-submodule-update / magit-submodule-add
forge-list-pull-requests / forge-read-issue
forge-create-issue TITLE BODY / forge-create-pull-request TITLE BODY BASE HEAD
forge-post-comment ISSUE-NUMBER-OR-URL BODY
```

## 5. Tests & Debugging

```bash
(+carlos/magent-tool-ert-runner "SELECTOR")   # isolated ERT run + smart stacktrace
(+carlos/magent-tool-debug ACTION &optional ARG1 ARG2)
```

## 6. Environment & DevOps

```bash
(+carlos/magent-tool-elpaca ACTION &optional PKG ARGS)  # package manager state
docker-ps / docker-logs / docker-action                 # containers (remote-host aware)
systemd-status / systemd-action / systemd-journal       # services (remote-host aware)
rfc-search-topic QUERY / rfc-read-section NUMBER SECTION
```

## 7. Model routing

```elisp
(+carlos/magent-tool-select-model ...) ; tier-aware model selection used by subagents
```

---

## Lessons learned (encode these habits)

1. **Never hand-count parentheses in bulk structural edits.** Build text via `pp` of real data, or make single-token anchored changes verified by `syntax-ppss` depth checks.
2. **Anchors must match reality byte-for-byte** — grep the file first; remember punctuation often lives inside string literals (e.g. `'.'` in format strings).
3. **Verify structure by depth, not by eye**: compare `(nth 0 (syntax-ppss))` across sibling forms; uniform depth == balanced siblings.
4. After ANY structural edit: `just compile` (zero-warning gate) before committing.

## Exceptions

- Throwaway scripts outside the project scope (`/tmp`) may use default write tools.
- If the user explicitly demands rigor even for throwaways, initialize them with `sh_smart_edit`.
